import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject var state: AppState
    var onOpenVersions: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            if let banner = state.banner {
                BannerView(banner: banner) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        state.banner = nil
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            heroStatusCard

            switch state.supportStatus {
            case .supported:
                supportedActionsCard
            case .unsupported(let build):
                unsupportedCard(build: build)
            case .noWeChat:
                noWeChatCard
            case .failed:
                detectionFailedCard
            case .unknown:
                loadingCard
            }
        }
        .animation(.easeInOut(duration: 0.18), value: state.banner)
    }

    // MARK: - Hero WeChat Status Card

    private var wechatIcon: NSImage {
        let icon = NSWorkspace.shared.icon(forFile: state.appPath)
        icon.size = NSSize(width: 128, height: 128)
        return icon
    }

    private var heroStatusCard: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .center, spacing: 15) {
                    ZStack(alignment: .bottomTrailing) {
                        Image(nsImage: wechatIcon)
                            .resizable()
                            .frame(width: 58, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: Color.black.opacity(0.10), radius: 5, x: 0, y: 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Theme.border, lineWidth: 1)
                            )

                        if state.installState == .installed {
                            ZStack {
                                Circle()
                                    .fill(Theme.surface)
                                    .frame(width: 22, height: 22)
                                Image(systemName: "checkmark.shield.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                            }
                            .offset(x: 4, y: 4)
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .center, spacing: 8) {
                            Text("微信 \(state.displayVersion)")
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            supportPill
                        }

                        HStack(spacing: 7) {
                            MonoChip(text: state.displayBuild, prefix: "Build")
                            installStatePill
                        }
                    }

                    Spacer(minLength: 8)

                    if state.busy {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            if !state.busyMessage.isEmpty {
                                Text(state.busyMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    } else {
                        IconCircleButton(
                            systemImage: "arrow.clockwise",
                            helpText: "重新检测微信状态",
                            disabled: state.busy
                        ) {
                            Task { await state.refresh() }
                        }
                    }
                }

                // Embedded compact target app path bar
                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(state.appPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(state.appPath)

                    Spacer(minLength: 8)

                    Button("更改…", action: chooseTargetApp)
                        .buttonStyle(SecondaryPillButtonStyle(compact: true))
                        .disabled(state.busy)

                    if !state.isUsingDefaultAppPath {
                        Button("重置") {
                            Task { await state.resetTargetApp() }
                        }
                        .buttonStyle(SecondaryPillButtonStyle(compact: true))
                        .disabled(state.busy)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                        .fill(Theme.surfaceSubtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private var supportPill: some View {
        switch state.supportStatus {
        case .supported:
            StatusPill(tone: .good, text: "版本受支持", systemImage: "checkmark.seal.fill")
        case .unsupported:
            StatusPill(tone: .warn, text: "暂不支持", systemImage: "exclamationmark.triangle.fill")
        case .noWeChat:
            StatusPill(tone: .neutral, text: "未找到微信", systemImage: "questionmark.circle")
        case .failed:
            StatusPill(tone: .bad, text: "检测异常", systemImage: "xmark.octagon.fill")
        case .unknown:
            StatusPill(tone: .neutral, text: "正在检测…")
        }
    }

    @ViewBuilder
    private var installStatePill: some View {
        switch state.installState {
        case .installed:
            StatusPill(
                tone: .good,
                text: state.withTip ? "提示模式生效中" : "静默模式生效中",
                systemImage: "sparkles"
            )
        case .notInstalled:
            StatusPill(tone: .neutral, text: "未开启补丁")
        case .mismatch:
            StatusPill(tone: .warn, text: "字节不匹配", systemImage: "exclamationmark.circle")
        case .unknown:
            EmptyView()
        }
    }

    // MARK: - Supported Mode Selector & Primary Action Card

    private var supportedActionsCard: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                SectionLabel(
                    text: "撤回拦截模式",
                    subtitle: "选择对方撤回消息后，微信聊天窗口内的呈现效果"
                )

                HStack(spacing: 12) {
                    ModePreviewCard(
                        selected: !state.withTip,
                        showsRecallTip: false,
                        icon: "eye.slash.fill",
                        title: "静默保留",
                        detail: "消息无痕留下，界面没有任何撤回打扰",
                        disabled: state.busy || !state.silentAvailable
                    ) {
                        if state.withTip { Task { await state.setWithTip(false) } }
                    }

                    ModePreviewCard(
                        selected: state.withTip,
                        showsRecallTip: true,
                        icon: "eye.fill",
                        title: "显示撤回提示",
                        detail: "保留原消息，同时在下方展示撤回提示",
                        disabled: state.busy || !state.tipAvailable
                    ) {
                        if !state.withTip { Task { await state.setWithTip(true) } }
                    }
                }

                if !state.tipAvailable {
                    HintRow(
                        systemImage: "info.circle.fill",
                        text: "当前微信构建号暂未提供「显示撤回提示」补丁，已自动锁定为静默保留模式。",
                        tint: Theme.info
                    )
                }

                Rectangle()
                    .fill(Theme.subtleDivider)
                    .frame(height: 1)

                // Unified smart action zone
                if state.wechatRunning {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.amber)
                            Text("安装或检查补丁前，请先完全退出正在运行的微信。")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            Task { await state.quitWeChat() }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "power")
                                Text("退出微信以继续")
                            }
                        }
                        .buttonStyle(PrimaryActionButtonStyle(variant: .amber))
                        .disabled(state.busy)
                    }
                } else {
                    Button {
                        Task { await state.install(InstallRequest(withTip: state.withTip)) }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: state.installState == .installed
                                  ? "arrow.triangle.2.circlepath"
                                  : "shield.lefthalf.filled")
                            Text(primaryInstallButtonTitle)
                        }
                    }
                    .buttonStyle(PrimaryActionButtonStyle(variant: .emerald))
                    .disabled(state.busy || !state.silentAvailable)
                }

                HStack(alignment: .center, spacing: 10) {
                    HStack(spacing: 5) {
                        Image(systemName: "lock.doc")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("仅支持官网 DMG 版微信 · 安装后自动重签名")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Button {
                        Task { await state.checkOnly(InstallRequest(withTip: state.withTip)) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "stethoscope")
                            Text("仅检查补丁点")
                        }
                    }
                    .buttonStyle(SecondaryPillButtonStyle(compact: true))
                    .disabled(state.busy || state.wechatRunning || !state.silentAvailable)
                }
            }
        }
    }

    private var primaryInstallButtonTitle: String {
        if state.installState == .installed {
            return "重新安装防撤回补丁"
        }
        return state.withTip ? "开启防撤回（显示提示）" : "开启静默防撤回"
    }

    // MARK: - Fallback / Empty State Cards

    private var loadingCard: some View {
        Card {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("正在读取微信版本与补丁状态…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
    }

    private func unsupportedCard(build: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Theme.amber.opacity(0.14))
                            .frame(width: 34, height: 34)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.amber)
                    }
                    SectionLabel(
                        text: "当前微信版本暂不支持",
                        subtitle: "本机微信构建号 \(build) 不在离线补丁支持列表中"
                    )
                }

                Text("为保证安全性与稳定性，本工具仅对已精确适配的官方构建号（270390 / 270416 / 270601）生效，不会从网络下载未知补丁。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let onOpenVersions {
                    Button {
                        onOpenVersions()
                    } label: {
                        Label("查看受支持的微信版本", systemImage: "list.bullet.rectangle")
                    }
                    .buttonStyle(SecondaryPillButtonStyle())
                }
            }
        }
    }

    private var noWeChatCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Theme.surfaceSubtle)
                            .frame(width: 34, height: 34)
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    SectionLabel(
                        text: "未检测到微信应用",
                        subtitle: "未能在目标路径找到官方 macOS 版微信"
                    )
                }

                Text("请确认已从微信官网安装 macOS 微信 4，或在上方点击「更改…」手动指定微信所在位置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button("手动选择微信…", action: chooseTargetApp)
                        .buttonStyle(SecondaryPillButtonStyle())
                        .disabled(state.busy)

                    Button("重新检测") {
                        Task { await state.refresh() }
                    }
                    .buttonStyle(SecondaryPillButtonStyle())
                    .disabled(state.busy)
                }
            }
        }
    }

    private var detectionFailedCard: some View {
        Card {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.danger.opacity(0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("未能完成版本检测")
                        .font(.subheadline.weight(.semibold))
                    Text("请参考上方横幅提示处理，或重新选择完整的官方微信 App。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("重新检测") {
                    Task { await state.refresh() }
                }
                .buttonStyle(SecondaryPillButtonStyle())
                .disabled(state.busy)
            }
        }
    }

    private func chooseTargetApp() {
        let panel = NSOpenPanel()
        panel.title = "选择官方 macOS 微信"
        panel.message = "请选择微信 App。本精简版不支持多开副本。"
        panel.prompt = "选择"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: state.appPath).deletingLastPathComponent()

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await state.selectTargetApp(at: url) }
    }
}

// MARK: - Interactive Mode Card with Mini Chat Bubble Preview

private struct ModePreviewCard: View {
    let selected: Bool
    let showsRecallTip: Bool
    let icon: String
    let title: String
    let detail: String
    let disabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 11) {
                MiniChatPreview(showsRecallTip: showsRecallTip, highlighted: selected)

                HStack(spacing: 7) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selected ? Theme.accent : .secondary)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selected ? Theme.accent : Color.secondary.opacity(0.35))
                }

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(selected
                          ? Theme.accentSoft
                          : (isHovered && !disabled ? Theme.surfaceHover : Theme.surfaceSubtle))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        selected ? Theme.accent : Theme.border,
                        lineWidth: selected ? 1.6 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1.0)
        .animation(.easeOut(duration: 0.15), value: selected)
        .onHover { isHovered = $0 }
    }
}

private struct MiniChatPreview: View {
    let showsRecallTip: Bool
    let highlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 7) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(highlighted ? Theme.accent.opacity(0.22) : Color.secondary.opacity(0.16))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(highlighted ? Theme.accent : .secondary)
                    )

                Text("今晚八点老地方见")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Theme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 0.8)
                    )

                Spacer(minLength: 0)
            }

            HStack {
                Spacer(minLength: 0)
                if showsRecallTip {
                    Text("对方撤回了一条消息")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.12))
                        )
                } else {
                    Text("无撤回提示 · 静默保留")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(highlighted ? Theme.accent : .secondary.opacity(0.75))
                        .padding(.vertical, 2)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.canvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Theme.subtleDivider, lineWidth: 1)
        )
    }
}
