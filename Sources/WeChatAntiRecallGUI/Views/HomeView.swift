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

    // MARK: - Card 1: Hero WeChat Status & Path

    private var wechatIcon: NSImage {
        let icon = NSWorkspace.shared.icon(forFile: state.appPath)
        icon.size = NSSize(width: 96, height: 96)
        return icon
    }

    private var heroStatusCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack(alignment: .bottomTrailing) {
                        Image(nsImage: wechatIcon)
                            .resizable()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1.5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(Theme.border, lineWidth: 1)
                            )

                        if state.installState == .installed {
                            ZStack {
                                Circle()
                                    .fill(Theme.surface)
                                    .frame(width: 18, height: 18)
                                Image(systemName: "checkmark.shield.fill")
                                    .font(.system(size: 11.5, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                            }
                            .offset(x: 3, y: 3)
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .center, spacing: 7) {
                            Text("微信 \(state.displayVersion)")
                                .font(.system(size: 16.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            supportPill
                        }

                        HStack(spacing: 6) {
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

                Rectangle()
                    .fill(Theme.subtleDivider)
                    .frame(height: 1)

                HStack(spacing: 8) {
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
                        .fixedSize(horizontal: true, vertical: false)
                        .disabled(state.busy)

                    if !state.isUsingDefaultAppPath {
                        Button("重置") {
                            Task { await state.resetTargetApp() }
                        }
                        .buttonStyle(SecondaryPillButtonStyle(compact: true))
                        .fixedSize(horizontal: true, vertical: false)
                        .disabled(state.busy)
                    }
                }
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

    // MARK: - Card 2: Patch Configuration & Compact Actions

    private var modeSubtitle: String {
        (state.withTip && state.tipAvailable)
            ? "保留被撤回消息，并在下方展示原生撤回提示"
            : "无痕保留被撤回消息，聊天窗口无任何撤回打扰"
    }

    private var supportedActionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("撤回拦截模式")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text(modeSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    CompactModeSegmentPicker(
                        withTip: Binding(
                            get: { state.withTip },
                            set: { newValue in
                                Task { await state.setWithTip(newValue) }
                            }
                        ),
                        tipAvailable: state.tipAvailable,
                        disabled: state.busy
                    )
                }

                Rectangle()
                    .fill(Theme.subtleDivider)
                    .frame(height: 1)

                if state.wechatRunning {
                    HStack(alignment: .center, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.amber)
                            Text("修改或预检补丁前需先退出主微信")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Button {
                            Task { await state.quitWeChat() }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "power")
                                    .font(.system(size: 11.5, weight: .semibold))
                                Text("退出微信")
                            }
                        }
                        .buttonStyle(CompactPrimaryPillButtonStyle(variant: .amber))
                        .fixedSize(horizontal: true, vertical: false)
                        .disabled(state.busy)
                    }
                } else {
                    HStack(alignment: .center, spacing: 10) {
                        HStack(spacing: 5) {
                            Image(systemName: "lock.doc")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text("仅支持官网 DMG 版 · 自动备份并重签名")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        HStack(spacing: 8) {
                            Button {
                                Task { await state.checkOnly(InstallRequest(withTip: state.withTip)) }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "stethoscope")
                                    Text("仅预检")
                                }
                            }
                            .buttonStyle(SecondaryPillButtonStyle(compact: true))
                            .fixedSize(horizontal: true, vertical: false)
                            .disabled(state.busy || !state.silentAvailable)

                            Button {
                                Task { await state.install(InstallRequest(withTip: state.withTip)) }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: state.installState == .installed
                                          ? "arrow.triangle.2.circlepath"
                                          : "shield.lefthalf.filled")
                                        .font(.system(size: 11.5, weight: .semibold))
                                    Text(state.installState == .installed ? "重新安装" : "开启防撤回")
                                }
                            }
                            .buttonStyle(CompactPrimaryPillButtonStyle(variant: .emerald))
                            .fixedSize(horizontal: true, vertical: false)
                            .disabled(state.busy || !state.silentAvailable)
                        }
                    }
                }
            }
        }
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
            .padding(.vertical, 2)
        }
    }

    private func unsupportedCard(build: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Theme.amber.opacity(0.14))
                            .frame(width: 32, height: 32)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.amber)
                    }

                    SectionLabel(
                        text: "当前微信版本暂不支持",
                        subtitle: "本机微信构建号 \(build) 不在离线补丁支持列表中"
                    )

                    Spacer(minLength: 8)

                    if let onOpenVersions {
                        Button {
                            onOpenVersions()
                        } label: {
                            Label("查看支持版本", systemImage: "list.bullet.rectangle")
                        }
                        .buttonStyle(SecondaryPillButtonStyle(compact: true))
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }

                Text("为保证安全性与稳定性，本工具仅对已精确适配的官方构建号生效，不会从网络下载未知补丁。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var noWeChatCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Theme.surfaceSubtle)
                            .frame(width: 32, height: 32)
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    SectionLabel(
                        text: "未检测到微信应用",
                        subtitle: "未能在目标路径找到官方 macOS 版微信"
                    )

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        Button("选择微信…", action: chooseTargetApp)
                            .buttonStyle(SecondaryPillButtonStyle(compact: true))
                            .fixedSize(horizontal: true, vertical: false)
                            .disabled(state.busy)

                        Button("重新检测") {
                            Task { await state.refresh() }
                        }
                        .buttonStyle(SecondaryPillButtonStyle(compact: true))
                        .fixedSize(horizontal: true, vertical: false)
                        .disabled(state.busy)
                    }
                }

                Text("请确认已从微信官网安装 macOS 微信 4，或点击右上角「选择微信…」手动指定微信所在位置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var detectionFailedCard: some View {
        Card {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.danger.opacity(0.14))
                        .frame(width: 32, height: 32)
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                }

                SectionLabel(
                    text: "未能完成版本检测",
                    subtitle: "请参考上方横幅提示处理，或重新选择完整的官方微信 App"
                )

                Spacer(minLength: 8)

                Button("重新检测") {
                    Task { await state.refresh() }
                }
                .buttonStyle(SecondaryPillButtonStyle(compact: true))
                .fixedSize(horizontal: true, vertical: false)
                .disabled(state.busy)
            }
        }
    }

    private func chooseTargetApp() {
        let panel = NSOpenPanel()
        panel.title = "选择官方 macOS 微信"
        panel.message = "首页用于管理官方主微信；如需创建或管理多开分身，请前往「微信多开」页。"
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
