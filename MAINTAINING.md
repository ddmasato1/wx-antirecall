# 维护指南（静默版）

这个分支是上游 `fzlzjerry/wechat-antirecall` 的功能删减版。维护目标是**保持小版本矩阵、单功能的安装链路稳定**，而不是继续扩展功能。

## 不可变事实

- 支持矩阵只有两项：`270390`（微信 4.2.0.54）和 `270416`（本机 4.2.0）。
- `patches.json` 每个条目里只有一个 target：`revoke`。
- `revoke` 只有一条 arm64 补丁：`Contents/Resources/wechat.dylib`，`40100034` → `82000014`：
  - `270390`：`0x461413c`
  - `270416`：`0x4666e98`
- 没有 dylib 注入，没有运行时 hook，没有 `revoke-tip` / `runtime-tip` / `update` target。
- `patches.json.sha256` 必须与 `patches.json` 匹配；改动补丁数据后运行 `Scripts/hash-patches.sh`。当前校验和：`c4bb80b7f25abe53786d0a4b1819d5dbec207a896515505a19fe96151fa5488b`。

## 目录与职责

- `Sources/WeChatAntiRecall/CLI.swift`：`versions` / `install` / `restore` 三个命令，Mach-O 补丁引擎、备份、重签名、权限检查。
- `Sources/WeChatAntiRecall/JSONOutput.swift`：CLI 的 `--json` DTO；`jsonSchemaVersion = 2`。
- `Sources/WeChatAntiRecallGUI/`：SwiftUI 外壳，只通过子进程调用 CLI，不直接链接 CLI target。
- `Scripts/make-app.sh`：组装并签名 `dist/WeChatAntiRecall.app`。
- `Tests/WeChatAntiRecallTests/`：补丁配置不变量、安装状态判定、签名链路、进程路径判定。

CLI 与 GUI 的 JSON schema 分别在 `JSONOutput.swift` 与 `Model/UITypes.swift`，改动字段时必须同步。

## 安装链路

1. GUI 读取内置 `patches.json`，执行 `versions` 检测构建号。
2. `validateAppSignatureIsPatchable` 按渠道判定（见 `AppSignaturePolicy.classify`）：有 `Contents/_MASReceipt/receipt` 或 `Software Signing` Authority 时拒绝。**不要**用 `Signature=adhoc`、缺少 `Developer ID Application` Authority 或 `com.apple.provenance` 来拒绝——本工具安装完成后微信必然是 ad-hoc、TeamIdentifier 为空，按签名判定会让安装后的每次检测都失败。
3. 执行 `install --dry-run [--with-tip]`，确认每个字节匹配（`wouldPatch` / `alreadyPatched`）。
4. 探测写权限：用户可写则直接运行；root 拥有则提权；用户拥有但被 TCC 拦截则提示「完全磁盘访问」。
5. 真实安装：备份 `wechat.dylib` → 写入 4 字节 → ad-hoc 重签名 → 比对所有 entitlements。
6. 任一步 entitlements 不一致即中止，不会把结果标记为成功。

`injectDisableLibraryValidation` 保留是**必需的**：ad-hoc 重签名后微信会加载自带框架并执行匿名 RX 代码，没有这两个 entitlement 会立即崩溃。它和已删除的 dylib 无关，不要顺手删掉。

## 显示撤回提示（revoke-tip）

静默模式把 `parseRevokeXML` 入口的 `cbz w0` 改成无条件 `b`，整个撤回处理被跳过，所以连微信自带的提示都不显示。提示模式改为走完处理流程：

1. 把入口 `cbz` 恢复成原值 `40100034`（expected 允许 `40100034` / `82000014` 两种前置态）。
2. 把 `newMsgId` 字段写入 `str x0,[x19,#0x1c8]`（`60E600F9`）改成 `str xzr`（`7FE600F9`）。

微信照常生成原生撤回提示，但按 newMsgId 定位不到原消息，所以消息保留。`--with-tip` 只选 `revoke-tip` target，与 `revoke` 互斥（两者都改 `0x461413c`，绝不能同时安装）。切换模式会新建一份备份，恢复时请在列表里选最早的那份（原始字节）。混合态（`alreadyPatched` + `wouldPatch`）在 `InstallState.classify` 里判为「未开启」，属于正常的模式切换中间态。

270416 的 `revoke-tip` 地址未定位（缺二进制样本），因此只提供静默模式；GUI 按 `installedBuildTargets` 禁用提示选择器。

## 新增构建号的定位方法

`revoke` 补丁的本质是把 `parseRevokeXML` 入口处的一条 `cbz w0, #imm`（字节 `40100034`）改成 `b`（`82000014`），跳过撤回时删除原消息的逻辑。新增构建时：

1. 提取 arm64 切片，解析 `LC_FUNCTION_STARTS`。
2. 搜索 `40100034`，每个命中映射到所在函数，核对几何特征：函数 `0x111c`（或重编译后的 `0x1164`）字节、分支在入口 `+0x270`（重编译后 `+0x278`）、`str x0,[x19,#0x1c8]`（`60e600f9`）在 `+0xa10`（重编译后 `+0xa40`）、分支解码目标与 `82000014` 一致。
3. 核对唯一直接调用点位于入口 `-0x84`（重编译后 `-0x80`）。
4. 在整片中确保满足以上特征的候选唯一。
5. 写进 `patches.json` 后重算 `patches.json.sha256`，并用 `install --dry-run --json` 在真实 dylib 上确认 `wouldPatch`。

270416 的样本指纹（未修改）：

- 完整 universal `wechat.dylib` SHA-256：`57113ff28b0fcd52f53749fc447695d70226162f654cb4856b7748a58c95930a`
- arm64 切片 SHA-256：`9e437ad6b0ff077137655058a318cee417cb32926e3a8b19be81714d816c3f48`

## 不要做的事

- 不要恢复 GUI 的「检查更新 / 拉取补丁数据」。它会把上游多版本 catalog 下载到 Application Support 并覆盖内置数据表，破坏受控版本矩阵。
- 不要恢复 `runtime-tip` 或任何 dylib 注入。补丁入口改写与 dylib hook 必须成对出现，单独恢复会让微信在第一次撤回时跳到空槽崩溃。
- 不要给 `install` 加回功能 flag。CLI 现在只接受 `--app`、`--config`、`--dry-run`、`--no-backup`、`--skip-resign`、`--json`。
- 不要手动编辑微信 App，永远走备份 → 补丁 → 签名链路。

## 验证

```bash
swift build
swift build -c release --arch arm64
swift test              # 需要完整 Xcode；只有 Command Line Tools 会因缺少 XCTest 失败
bash Scripts/hash-patches.sh
```

已在 270416 的 App 副本上完成：`wouldPatch` 检测 → 实际写入（`40100034`→`82000014`）→ 生成备份 → 重复安装返回 `alreadyPatched` → `codesign --verify --deep --strict` 通过 → 从备份恢复（`82000014`→`40100034`）并重签名通过。这一步使用临时副本跳过本机沙箱对 Swift 启动 `/bin/ps` 的 EPERM 限制，产品代码未改。

发布：`git tag vX.Y.Z && git push --tags`，release workflow 会构建 `.app`、生成 DMG 并发布。发布说明里不要写「拉取最新补丁数据」。
