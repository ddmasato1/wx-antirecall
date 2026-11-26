# 微信防撤回（静默版）

**只做一件事：让受支持构建里别人撤回的消息原样保留。** 可选两种效果：静默保留，或保留的同时显示微信原生的「xxx 撤回了一条消息」提示。

## 支持的版本

| 微信版本 | 构建号 | 来源 |
| --- | --- | --- |
| 4.2.0.54 | **270390** | 官网 dmg（补丁点双重验证） |
| 4.2.0 | **270416** | 曾为 App Store 渠道版本（仅静默） |
| 4.2.1 | **270601** | 官网当前版本（静默 + 提示均支持，已真机验证） |

其他构建号一律拒绝安装，也不会拉取新版补丁数据。

## 两种显示效果

| 模式 | 效果 | 支持的构建号 |
| --- | --- | --- |
| 静默保留（默认） | 原消息留下，不显示任何提示 | 270390 / 270416 / 270601 |
| 显示撤回提示 | 原消息留下，同时显示微信原生撤回提示 | 270390 / 270601 |

在首页的两张模式卡片里选择，再点开启即可。两种模式都是**纯字节补丁**，不需要注入 dylib、不需要常驻进程、不需要自定义提示文本。

原理差别（按构建）：

- **270390 / 270416**：静默模式把撤回解析器入口的 `cbz w0` 改成无条件 `b`，整个撤回处理被跳过，所以连微信自带提示都不显示。
- **270601**：撤回解析器重构（`0x413bca8` 起 `0xa30` 字节），静默改为把「`revokemsg` 节点闸门」`cbz w0`（`0x413be8c`，`00180034`）改成 `NOP`（`1F2003D5`）——撤回消息会走「找不到节点 → 记日志 → 返回 0」的现成安全路径，与其他 sysmsg 类型一致。
- 提示模式（270390 与 270601 同理）：把 `newMsgId` 字段写入 `str x0,[x19,#0x1c8]`（`60E600F9`）改成 `str xzr`（`7FE600F9`）——微信照常生成原生撤回提示，却按 newMsgId 找不到原消息，于是消息保留。270601 的写入点在 `0x413c238`，与静默点地址独立，模式切换互不干扰。

**已知限制**（上游实测说明）：提示模式是纯字节补丁，你自己撤回消息时桌面端可能留下重复的撤回提示；别人撤回是正常场景。270416 的提示补丁点未定位（缺二进制样本），暂只提供静默模式。

## 不支持 App Store 版微信

本工具会对微信做 ad-hoc 重签名。**Mac App Store 安装的微信不能用**：它由 Apple 的 `Software Signing` 身份签名；ad-hoc 重签会破坏该签名，导致微信无法启动。官网 dmg 版由 Tencent 的 Developer ID 签名，重签后可以启动。

安装前工具按**渠道**判断，而不是按当前签名状态（也不是 provenance 属性）：
- 存在 `Contents/_MASReceipt/receipt`（App Store 收据）或签名为 `Software Signing` → 拒绝，不写任何字节
- 官网 dmg 的 `Developer ID Application: Tencent ...` → 放行
- 已经是 ad-hoc 签名 → **照样放行**：这正是本工具成功开启后的正常状态。早期版本按 ad-hoc 拒绝，导致装完每次检测都误报「检测失败」，已修正。

如果已经把 App Store 版微信改到无法启动：本工具无法修复（补丁只改 dylib 字节，不会还原 Apple 原始签名）。请卸载微信后重新安装，聊天记录保留在 `~/Library/Containers/com.tencent.xinWeChat/`。

## 版本与渠道提示

- 270601（4.2.1，官网当前版本）已支持，正常升级即可使用本工具。
- 如需回退 270390：注意官方直链 `WeChatMac_4.2.0.dmg` 的内容**会被腾讯换货**（2026-11 中旬曾换成 4.2.1 内容，GitHub/uptodown 的「4.2.0.54」归档同样不可信）。可靠的 270390 dmg 备份见本地 `~/Downloads/WeChatMac_4.2.0.54-270390.dmg`（dylib SHA-256 `685914bf…eecd2b8`），务必异地再存一份。
- 无论哪个版本，安装补丁后都建议在微信设置里关闭「有新版本时自动升级微信」。

## 这个版本删掉了什么

- 只保留**防撤回**：`patches.json` 里只有 `revoke` / `revoke-tip` 两个 target（270416 只有 `revoke`）。
- 删除了自定义提示、撤回记录、关键词提醒、窗口隐私、自动红包、微信多开、屏蔽自动更新、检查更新/源码构建。
- 删除了注入微信的运行时 dylib（`libWeChatAntiRecallRuntime.dylib`）及其全部 hook 代码。

保留的通用链路：版本检测、dry-run 预检、备份、二进制补丁、重签名与 entitlements 校验、权限引导。GUI 的「恢复 / 卸载」界面已删除（恢复请重装官网版微信，见「权限与帮助」页说明）；CLI 的 `restore` 子命令保留，作为开发者自救通道。

## 支持的平台

- Apple Silicon（M 系列）Mac，macOS 12+
- 上表中的三个微信构建号
- 不适配 Intel Mac，不适配其他微信构建号

## 使用

1. 完全退出微信。
2. 打开「微信防撤回」App（首次打开需右键 → 打开）。
3. 首页确认构建号在支持列表内，选一种模式，点「开启防撤回」。
4. 重新打开微信。用另一账号发一条消息并撤回，确认原消息仍在。

恢复：本版本不在 GUI 里提供恢复/卸载。如需恢复到原版微信，完全退出微信后从官网下载受支持版本的安装包重新安装覆盖即可（聊天记录不丢失）；开发者可用 CLI 的 `restore` 子命令从备份还原。

## 命令行

在仓库根目录：

```bash
swift build -c release --product wechat-antirecall
WXAR_CLI="$(swift build -c release --show-bin-path)/wechat-antirecall"

# 查看支持的版本
"$WXAR_CLI" versions --app /Applications/WeChat.app --config ./patches.json

# 只检查，不修改
"$WXAR_CLI" install --dry-run --app /Applications/WeChat.app --config ./patches.json

# 安装（需先退出微信）
"$WXAR_CLI" install --app /Applications/WeChat.app --config ./patches.json

# 从备份恢复
"$WXAR_CLI" restore --app /Applications/WeChat.app \
  --binary Contents/Resources/wechat.dylib \
  --backup /Applications/WeChat.app/Contents/Resources/wechat.dylib.wechat-antirecall-backup-YYYYMMDD-HHMMSS
```

`install` 只接受通用参数：`--app`、`--config`、`--dry-run`、`--no-backup`、`--skip-resign`、`--json`。传入已删除功能的参数会直接报错。

## 构建图形界面

```bash
bash Scripts/make-icon.sh
bash Scripts/make-app.sh
open dist/AntiRecall.app
```

打包产物包含 GUI、CLI、`patches.json` 和图标，不再包含 dylib。

## 补丁内容

全部是单条 arm64 指令替换（每处 4 字节），`patches.json` 为唯一事实来源：

| 构建号 | target | 地址 | 原始字节 | 补丁字节 |
| --- | --- | --- | --- | --- |
| 270390 | revoke | `0x461413c` | `40100034` | `82000014` |
| 270390 | revoke-tip | `0x461413c` / `0x4614904` | `60E600F9` | `7FE600F9` |
| 270416 | revoke | `0x4666e98` | `40100034` | `82000014` |
| 270601 | revoke | `0x413be8c` | `00180034` | `1F2003D5` |
| 270601 | revoke-tip | `0x413c238` | `60E600F9` | `7FE600F9` |

（revoke-tip 先把入口恢复原值再改写 newmsgid 写入指令，见 MAINTAINING.md。）

修改后整包 ad-hoc 重签名，并逐项比对 entitlements；不一致则中止安装。

270416 的补丁点由本机构建直接定位：`parseRevokeXML` 函数 `0x4666c28`–`0x4667d44`（`0x111c` 字节），静默分支在入口 `+0x270`，`newmsgid` 写入在 `+0xa10`，唯一直接调用点在 `0x4666ba4`（入口 `-0x84`）。这组几何特征与已验证的 270352 完全一致，并在整个 arm64 切片中唯一命中；分支跳转目标 `0x46670a0` 与补丁字节解码一致。

270601 的撤回解析器被重构（`0x413bca8` 起 `0xa30` 字节），用 Capstone 全量反汇编并与 270390 已验证函数做骨架对齐定位，方法与几何特征记录在 MAINTAINING.md。

## 已知限制

- 微信升级到上表以外的构建后，工具会显示「暂不支持」。本分支不提供其他版本适配。
- 安装会改变微信签名身份。官网 dmg 版本安装后若打不开，给 `/Applications/WeChat.app` 授予「完全磁盘访问」；App Store 版本不支持，必须重装官网 dmg 版本。
- 提示模式是纯字节补丁，你自己撤回消息时桌面端可能留下重复的撤回提示；别人撤回是正常场景。
- 270601 残留风险：解析器中存在 `revoketime` 节点存在时走 `0x413c324` 的支路（解析 content/replacemsg，不写 newmsgid）。真机验证已通过（静默 + 提示），但若未来小版本重编译，优先复查该支路。
- 270416 未经真实账号撤回实测（缺真机环境），只完成了写入、备份、签名与恢复的静态验证；270390 与 270601 已真机验证。
- 静态检查和真实撤回效果不是一回事，务必按上面的步骤实测。
- 本机若只有 Command Line Tools 而没有完整 Xcode，`swift test` 会因缺少 XCTest 模块失败；`swift build` 正常。

维护说明见 [MAINTAINING.md](MAINTAINING.md)。

---

参考项目：[fzlzjerry/wechat-antirecall](https://github.com/fzlzjerry/wechat-antirecall)
