# 微信防撤回（静默版）

基于 [fzlzjerry/wechat-antirecall](https://github.com/fzlzjerry/wechat-antirecall) 的功能删减分支。

**只做一件事：让受支持构建里别人撤回的消息原样保留。** 可选两种效果：静默保留，或保留的同时显示微信原生的「xxx 撤回了一条消息」提示。

## 支持的版本

| 微信版本 | 构建号 | 来源 |
| --- | --- | --- |
| 4.2.0.54 | **270390** | 官网 dmg（推荐，补丁点双重验证） |
| 4.2.0 | **270416** | 曾为 App Store 渠道版本 |
| 4.2.1 | 270601 | **暂不支持**：撤回解析器已重构，静默分支未定位 |

其他构建号一律拒绝安装，也不会拉取新版补丁数据。

## 两种显示效果

| 模式 | 效果 | 支持的构建号 |
| --- | --- | --- |
| 静默保留（默认） | 原消息留下，不显示任何提示 | 270390 / 270416 |
| 显示撤回提示 | 原消息留下，同时显示微信原生撤回提示 | **仅 270390** |

在首页的「静默保留 / 显示撤回提示」选择器里切换，再点开启即可。两种模式都是**纯字节补丁**（各改 4 字节），不需要注入 dylib、不需要常驻进程、不需要自定义提示文本。

原理差别：静默模式把撤回解析器入口的 `cbz w0` 改成无条件 `b`，整个撤回处理被跳过，所以连微信自带提示都不显示；提示模式改为走完撤回流程，但把 `newMsgId` 字段写入 `str x0,[x19,#0x1c8]`（`60E600F9`）改成 `str xzr`（`7FE600F9`）——微信照常生成原生撤回提示，却按 newMsgId 找不到原消息，于是消息保留。

**已知限制**（上游实测说明）：提示模式是纯字节补丁，你自己撤回消息时桌面端可能留下重复的撤回提示；别人撤回是正常场景。270416 的提示补丁点未定位（缺二进制样本），暂只提供静默模式。

## 不支持 App Store 版微信

本工具会对微信做 ad-hoc 重签名。**Mac App Store 安装的微信不能用**：它由 Apple 的 `Software Signing` 身份签名；ad-hoc 重签会破坏该签名，导致微信无法启动。官网 dmg 版由 Tencent 的 Developer ID 签名，重签后可以启动。

安装前工具按**渠道**判断，而不是按当前签名状态（也不是 provenance 属性）：
- 存在 `Contents/_MASReceipt/receipt`（App Store 收据）或签名为 `Software Signing` → 拒绝，不写任何字节
- 官网 dmg 的 `Developer ID Application: Tencent ...` → 放行
- 已经是 ad-hoc 签名 → **照样放行**：这正是本工具成功开启后的正常状态。早期版本按 ad-hoc 拒绝，导致装完每次检测都误报「检测失败」，已修正。

如果已经把 App Store 版微信改到无法启动：**恢复按钮救不回来**（它只还原 dylib 字节，不会还原 Apple 原始签名）。请卸载微信后重新安装，聊天记录保留在 `~/Library/Containers/com.tencent.xinWeChat/`。

## 需要降级时

官网首页现在给的是 4.2.1 (270601)，暂不支持。安装 4.2.0.54 (270390) 请用官方直链：

```
https://dldir1v6.qq.com/weixin/Universal/Mac/WeChatMac_4.2.0.dmg
```

SHA-256：`04933657d5c3a3445bd7c07859a7a9b7e6f3437c2e19b5df6984e3179c25b6ca`（内容随官网更新，装前先核对构建号显示为 270390）。降级后可能需要重新登录并重新同步近期消息；**不要点微信内的更新提示**，升级到 270601 会让防撤回失效。

## 这个版本删掉了什么

- 只保留**防撤回**：`patches.json` 里只有 `revoke` / `revoke-tip` 两个 target（270416 只有 `revoke`）。
- 删除了自定义提示、撤回记录、关键词提醒、窗口隐私、自动红包、微信多开、屏蔽自动更新、检查更新/源码构建。
- 删除了注入微信的运行时 dylib（`libWeChatAntiRecallRuntime.dylib`）及其全部 hook 代码。

保留的通用链路：版本检测、dry-run 预检、备份、二进制补丁、重签名与 entitlements 校验、恢复/卸载、权限引导。

## 支持的平台

- Apple Silicon（M 系列）Mac，macOS 12+
- 上表中的两个微信构建号
- 不适配 Intel Mac，不适配其他微信构建号

## 使用

1. 完全退出微信。
2. 打开「微信防撤回」App（首次打开需右键 → 打开）。
3. 首页确认构建号在支持列表内，点「开启静默防撤回」。
4. 重新打开微信。用另一账号发一条消息并撤回，确认原消息仍在。

卸载：侧栏「恢复 / 卸载」选择备份时间戳 → 「还原这一次」。

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
open dist/WeChatAntiRecall.app
```

打包产物包含 GUI、CLI、`patches.json` 和图标，不再包含 dylib。

## 补丁内容

两个构建都是单条 arm64 指令替换，把 `cbz` 改成无条件跳转，跳过撤回时删除原消息的逻辑：

| 构建号 | 地址 | 原始字节 | 补丁字节 |
| --- | --- | --- | --- |
| 270390 | `0x461413c` | `40100034` | `82000014` |
| 270416 | `0x4666e98` | `40100034` | `82000014` |

修改后整包 ad-hoc 重签名，并逐项比对 entitlements；不一致则中止安装。

270416 的补丁点由本机构建直接定位：`parseRevokeXML` 函数 `0x4666c28`–`0x4667d44`（`0x111c` 字节），静默分支在入口 `+0x270`，`newmsgid` 写入在 `+0xa10`，唯一直接调用点在 `0x4666ba4`（入口 `-0x84`）。这组几何特征与已验证的 270352 完全一致，并在整个 arm64 切片中唯一命中；分支跳转目标 `0x46670a0` 与补丁字节解码一致。

## 已知限制

- 微信升级到上表以外的构建后，工具会显示「暂不支持」。本分支不提供其他版本适配。
- 安装会改变微信签名身份。官网 dmg 版本安装后若打不开，给 `/Applications/WeChat.app` 授予「完全磁盘访问」；App Store 版本不支持，必须重装官网 dmg 版本。
- 官网 4.2.1 (270601) 已定位撤回解析器函数 `0x413bca8`（13 处撤回字段引用 + `newmsgid` 写入 `60E600F9` 命中），但解析器被重构（`0xa30` 字节，此前为 `0x111c`），静默分支未找到唯一命中。适配它需要用 270390 的函数做地址立即数归一化对照，未完成。
- 静态检查和真实撤回效果不是一回事，务必按上面的步骤实测。本分支只在本机 270416 上完成了二进制写入、备份、签名和恢复的静态验证，**尚未做真实账号的撤回实测**。
- 本机若只有 Command Line Tools 而没有完整 Xcode，`swift test` 会因缺少 XCTest 模块失败；`swift build` 正常。

维护说明见 [MAINTAINING.md](MAINTAINING.md)。
