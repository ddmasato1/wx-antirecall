import SwiftUI
import AppKit

struct PermissionsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            privacyPermissionsCard
            securityAndRecoveryCard
        }
    }

    // MARK: - Card 1: System Privacy Permissions

    private var privacyPermissionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                SectionLabel(
                    text: "系统隐私权限",
                    subtitle: "仅在遇到对应系统拦截提示时按需配置"
                )

                Rectangle()
                    .fill(Theme.subtleDivider)
                    .frame(height: 1)

                permissionRow(
                    icon: "app.badge.checkmark",
                    tint: Theme.accent,
                    title: "App 管理权限",
                    badge: "按需授权本工具",
                    detail: "修改「应用程序」目录中的微信需写入许可；若安装时提示 Operation not permitted，请为本工具开启授权。",
                    buttonTitle: "打开 App 管理",
                    url: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles"
                )

                Rectangle()
                    .fill(Theme.subtleDivider)
                    .frame(height: 1)

                permissionRow(
                    icon: "externaldrive.badge.person.crop",
                    tint: Theme.info,
                    title: "完全磁盘访问权限",
                    badge: "打不开时配置",
                    detail: "本地重签名会改变原厂签名身份。若新版 macOS 拦截微信读取数据目录导致打不开，请将「微信」加入列表（重打补丁或升级后可能需重新添加）。",
                    buttonTitle: "打开磁盘访问",
                    url: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
                )
            }
        }
    }

    private func permissionRow(
        icon: String,
        tint: Color,
        title: String,
        badge: String,
        detail: String,
        buttonTitle: String,
        url: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 18, alignment: .center)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(badge)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(tint.opacity(0.12)))

                Spacer(minLength: 8)

                Button {
                    if let u = URL(string: url) {
                        NSWorkspace.shared.open(u)
                    }
                } label: {
                    Label(buttonTitle, systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(SecondaryPillButtonStyle(compact: true))
                .fixedSize(horizontal: true, vertical: false)
            }

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(1.5)
                .padding(.leading, 25)
        }
    }

    // MARK: - Card 2: Security & Recovery Guide

    private var securityAndRecoveryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    SectionLabel(
                        text: "安全机制与恢复指南",
                        subtitle: "常见疑问与原版还原说明"
                    )

                    Spacer(minLength: 8)

                    Button {
                        if let url = URL(string: "https://weixin.qq.com") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("访问微信官网", systemImage: "safari")
                    }
                    .buttonStyle(SecondaryPillButtonStyle(compact: true))
                    .fixedSize(horizontal: true, vertical: false)
                }

                guideRow(
                    icon: "checkmark.shield.fill",
                    tint: Theme.accent,
                    title: "无需关闭系统完整性保护（SIP）",
                    detail: "仅修改「应用程序」目录内的第三方微信文件，不触碰任何 macOS 系统受保护区域。"
                )

                Rectangle()
                    .fill(Theme.subtleDivider)
                    .frame(height: 1)

                guideRow(
                    icon: "testtube.2",
                    tint: Theme.amber,
                    title: "首次安装建议真机撤回验证",
                    detail: "补丁安装完成后，建议用另一账号或手机发送一条测试消息并撤回，确认消息留存效果符合预期。"
                )

                Rectangle()
                    .fill(Theme.subtleDivider)
                    .frame(height: 1)

                guideRow(
                    icon: "arrow.uturn.backward.circle.fill",
                    tint: .secondary,
                    title: "覆盖重装即可恢复原版微信",
                    detail: "退出微信后从官网下载安装包直接覆盖安装即可还原官方签名，独立数据目录中的本地聊天记录不会丢失。"
                )
            }
        }
    }

    private func guideRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1.5)
            }
        }
    }
}
