# AntiRecall 架构与维护指南

本文档说明 `AntiRecall`（`wx-antirecall`）的核心架构、补丁规格、重签名机制、多开分身设计以及新版本微信的适配方法。

## 核心约束与补丁矩阵

- **支持构建矩阵**：`270390`（微信 4.2.0.54）、`270416`（微信 4.2.0）、`270601`（微信 4.2.1）。`patches.json` 的 `wechatVersion` 键供 GUI「支持版本」页展示，CLI 解码时忽略。
- **补丁目标（Target）**：仅包含 `revoke`（静默保留）与 `revoke-tip`（显示撤回提示）两类纯字节补丁；`270390` / `270601` 同时提供两类目标，`270416` 仅提供 `revoke`。
- **`revoke` 补丁**（`Contents/Resources/wechat.dylib`）：
  - `270390`：`0x461413c`，`40100034` → `82000014`
  - `270416`：`0x4666e98`，`40100034` → `82000014`
  - `270601`：`0x413be8c`，`00180034` → `1F2003D5`（NOP）
- **`revoke-tip` 补丁**（保留入口流程，将 `newMsgId` 字段写入改写为 `str xzr`）：
  - `270390`：`0x461413c` 恢复 `40100034` + `0x4614904` `60E600F9` → `7FE600F9`（两处同函数，地址耦合）
  - `270601`：`0x413c238` `60E600F9` → `7FE600F9`（与静默点地址独立）
- **纯离线零注入**：不注入外部 `dylib`，无后台常驻进程，不从网络拉取外部补丁表。
- **校验和约束**：`patches.json.sha256` 必须与 `patches.json` 严格匹配；修改补丁表后需运行 `Scripts/hash-patches.sh`。当前校验和：`e68497473c8690070f10713bbdf5837fe5cc8d9893897aea0262a4d87056876c`。

## 目录结构与职责

- `Sources/AntiRecallCLI/CLI.swift`：`versions` / `install` / `restore` 命令与 `clone` 路由入口，Mach-O 补丁引擎、备份、重签名及权限检查。
- `Sources/AntiRecallCLI/Clone.swift`：`clone <list|create|remove>` 多开分身扫描、创建/无残留原子替换、本地化名称改写、Sparkle 自动更新禁用、补丁状态检测与安全删除。
- `Sources/AntiRecallCLI/JSONOutput.swift`：CLI 的 `--json` 输出协议 DTO；`jsonSchemaVersion = 3`。
- `Sources/AntiRecallGUI/`：原生 SwiftUI 界面（首页、微信多开、支持版本、权限帮助），通过子进程调用内置 `wx-antirecall` CLI，与 CLI Target 解耦。
- `Scripts/make-app.sh`：编译并组装签名 `dist/AntiRecall.app`（`com.github.ddmasato1.wx-antirecall`）。
- `Tests/AntiRecallTests/`：补丁配置不变量、安装状态分类、代码签名链路、进程路径匹配与多开分身全链路单元测试。

CLI 与 GUI 的 JSON 协议版本分别定义在 `JSONOutput.swift` 与 `Model/UITypes.swift`（`schemaVersion = 3`），修改字段时需同步更新。

## 防撤回安装与重签名链路

1. GUI 读取内置 `patches.json`，调用 `wx-antirecall versions` 检测目标微信构建号。
2. `validateAppSignatureIsPatchable` 校验渠道（见 `AppSignaturePolicy.classify`）：若存在 `Contents/_MASReceipt/receipt` 或 `Software Signing` Authority 则判定为 App Store 版并拒绝；官方 DMG 原厂签名与本工具重签名后的 ad-hoc 状态均放行。
3. 执行 `install --dry-run [--with-tip]` 预检每个补丁点字节（`wouldPatch` / `alreadyPatched`）。
4. 探测写权限：当前用户可写时直接执行；root 所有时通过 `osascript` 请求管理员授权；被 TCC 拦截时引导开启「App 管理 / 完全磁盘访问」。
5. 正式安装：备份 `wechat.dylib` → 写入 4 字节指令 → ad-hoc 重签名 → 逐项核对所有代码对象的 entitlements。
6. `injectDisableLibraryValidation` 在保留 Hardened Runtime 重签名主微信时注入 `com.apple.security.cs.disable-library-validation` 与 `com.apple.security.cs.allow-unsigned-executable-memory`，确保主程序加载内部框架及登录阶段执行匿名可执行内存页时不触发 AMFI 崩溃。

## 显示撤回提示（revoke-tip）原理

静默模式将 `parseRevokeXML` 入口的 `cbz w0` 改为跳过整个撤回解析分支，因此不产生任何撤回提示。提示模式则让撤回解析流程继续执行，但将 `newMsgId` 字段写入指令 `str x0,[x19,#0x1c8]`（`60E600F9`）改为 `str xzr,[x19,#0x1c8]`（`7FE600F9`），使微信照常生成「撤回了一条消息」系统提示，但因 `newMsgId` 为 0 而无法定位并删除原消息，从而实现「保留原消息 + 显示原生撤回提示」。

## 微信多开分身机制（clone）

- **独立 Bundle 身份**：将官方 `WeChat.app` 复制为 `/Applications/WeChat <N>.app`（槽位默认从 `2` 开始递增），改写 `CFBundleIdentifier` 为 `com.tencent.xinWeChat.antirecall.clone<N>`，写入分身标识元数据（`AntiRecallClone = true`，同时兼容旧键 `WeChatAntiRecallClone`），默认移除 `CFBundleURLTypes` 防止外部 `weixin://` 链接误唤起分身，并禁用分身内 Sparkle 自动更新（`SUEnableAutomaticChecks = false` 等）以消除后台 XPC 查找告警并防止自更新覆盖分身。
- **中英文显示名同步**：同步改写 `Contents/Info.plist` 与 `Contents/Resources/*.lproj/InfoPlist.strings`（`zh*` 写为 `微信 <N>`，其余写为 `WeChat <N>`），使 Finder、Dock 与菜单栏原生展示独立名称。
- **签名与数据隔离**：分身采用 `resign(..., preserveEntitlements: false)` 剥离绑定原厂 Team ID 的沙盒 entitlements 并以无 Hardened Runtime 的 ad-hoc 签名封包；微信 4 业务层按各自 `CFBundleIdentifier` 将账号聊天数据与 Mojo IPC 管道隔离在独立的 `~/Library/Containers/com.tencent.xinWeChat.antirecall.clone<N>/` 目录下。
- **跨模式切换与无残留重建**：创建或 `--replace` 同步重建分身支持 `--patch-mode none|silent|with-tip`；即使源主微信已打过另一模式的补丁，构造分身时也会自动将未选中 target 的独立补丁地址还原为 `expected[0]` 原始字节，并清理继承的备份文件。`--replace` 采用同目录隐藏暂存包原子切换并在成功后立即删除旧包，不在 `/Applications` 留下残留图标。
- **安全边界**：`--replace` 覆盖与 `clone remove` 均强制校验分身元数据标记，严禁覆盖或删除官方主微信及非本工具创建的应用。

## 270601（4.2.1）与新构建号定位方法

- **270601（4.2.1）补丁点**：
  - 解析器位于 `0x413bca8`（长 `0xa30` 字节）。
  - 静默补丁：`0x413be8c` 的 `cbz w0, 0x413c18c`（`00180034`）→ `NOP`（`1F2003D5`）。
  - 提示补丁：`0x413c238` 的 `str x0,[x19,#0x1c8]`（`60E600F9`）→ `str xzr`（`7FE600F9`）。
- **新增构建号通用定位流程**：
  1. 提取 `wechat.dylib` 的 `arm64` 切片，解析 `LC_FUNCTION_STARTS`。
  2. 通过经典特征（搜索 `40100034` 并核对函数尺寸、`+0x270/+0x278` 分支与 `[x19,#0x1c8]` 字段写入 `60e600f9`）或与已验证版本做反汇编骨架对齐（`bl` 调用、分支结构、`[x19,#0x1c0-0x1e0]` 字段写入、字符串引用锚点）唯一定位撤回解析函数。
  3. 更新 `patches.json`（附 `wechatVersion` 标注）后执行 `bash Scripts/hash-patches.sh` 更新校验和，并在真实二进制上通过 `install --dry-run --json` 验证。

## 构建与验证命令

```bash
swift build
swift build -c release --arch arm64
swift test
bash Scripts/hash-patches.sh
bash Scripts/make-app.sh
```
