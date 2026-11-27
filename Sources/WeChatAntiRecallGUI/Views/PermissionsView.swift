import SwiftUI
import AppKit

struct PermissionsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            permissionCard(
                icon: "app.badge.checkmark",
                tint: Theme.accent,
                title: "App 管理权限",
                badge: "按需授权本工具",
                body: "打补丁需要修改「应用程序」目录中的微信。若安装时提示「Operation not permitted」，请在此处为本工具开启授权。",
                buttonTitle: "打开 App 管理设置",
                url: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles"
            )

            permissionCard(
                icon: "externaldrive.badge.person.crop",
                tint: Theme.info,
                title: "完全磁盘访问权限",
                badge: "遇到打不开时配置",
                body: "安装会自动保留微信主程序及扩展的麦克风、摄像头、网络等权限声明；但本地重签名会改变原厂签名身份。若新版 macOS 因此拦截微信读取数据目录导致打不开，请将「微信」加入完全磁盘访问列表（重打补丁或升级微信后可能需删除旧项重新添加）。",
                buttonTitle: "打开完全磁盘访问设置",
                url: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
            )

            // Consolidated guide card for clean visual hierarchy
            Card(padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(
                        text: "安全机制与恢复指南",
                        subtitle: "常见疑问与原版还原说明"
                    )

                    guideItem(
                        icon: "checkmark.shield.fill",
                        tint: Theme.accent,
                        title: "无需关闭系统完整性保护（SIP）",
                        detail: "本工具仅修改「应用程序」目录内的第三方微信文件，不触碰任何 macOS 系统受保护区域。"
                    )

                    Rectangle()
                        .fill(Theme.subtleDivider)
                        .frame(height: 1)

                    guideItem(
                        icon: "testtube.2",
                        tint: Theme.amber,
                        title: "首次安装建议做一次真机实测",
                        detail: "补丁点校验通过后，建议用另一账号或手机发一条测试消息并撤回，确认消息留存效果符合预期。"
                    )

                    Rectangle()
                        .fill(Theme.subtleDivider)
                        .frame(height: 1)

                    VStack(alignment: .leading, spacing: 10) {
                        guideItem(
                            icon: "arrow.uturn.backward.circle.fill",
                            tint: .secondary,
                            title: "如何恢复到原版微信",
                            detail: "完全退出微信后，从微信官网下载安装包直接覆盖安装即可恢复原厂签名；本地聊天记录保存在独立数据目录中，覆盖重装不会丢失。"
                        )

                        HStack {
                            Spacer()
                            Button {
                                if let url = URL(string: "https://weixin.qq.com") {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Label("访问微信官网下载", systemImage: "safari")
                            }
                            .buttonStyle(SecondaryPillButtonStyle(compact: true))
                        }
                    }
                }
            }
        }
    }

    private func permissionCard(
        icon: String,
        tint: Color,
        title: String,
        badge: String,
        body text: String,
        buttonTitle: String,
        url: String
    ) -> some View {
        Card(padding: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(tint.opacity(0.13))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(badge)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(tint.opacity(0.12)))
                    }

                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                    } label: {
                        Label(buttonTitle, systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(SecondaryPillButtonStyle(compact: true))
                    .padding(.top, 2)
                }
            }
        }
    }

    private func guideItem(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
