import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            if let banner = state.banner {
                BannerView(banner: banner)
            }

            statusCard

            switch state.supportStatus {
            case .supported:
                supportedActions
            case .unsupported(let build):
                unsupportedCard(build: build)
            case .noWeChat:
                noWeChatCard
            case .failed:
                detectionFailedCard
            case .unknown:
                Card { ProgressView().controlSize(.small) }
            }
        }
    }

    // MARK: - Status card

    private var wechatIcon: NSImage {
        let icon = NSWorkspace.shared.icon(forFile: state.appPath)
        icon.size = NSSize(width: 112, height: 112)
        return icon
    }

    private var statusCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    Image(nsImage: wechatIcon)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 7) {
                        Text("微信 \(state.displayVersion)")
                            .font(.title2.weight(.semibold))
                        HStack(spacing: 8) {
                            MonoChip(text: state.displayBuild)
                            supportPill
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 8) {
                        if state.busy {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(state.busyMessage).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Button {
                            Task { await state.refresh() }
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise").font(.caption)
                        }
                        .buttonStyle(.link)
                        .disabled(state.busy)
                    }
                }

                Divider()

                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前微信 App")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(state.appPath)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(state.appPath)
                    }
                    Spacer(minLength: 12)
                    Button("选择…", action: chooseTargetApp)
                        .buttonStyle(.bordered)
                        .disabled(state.busy)
                    Button("恢复默认") {
                        Task { await state.resetTargetApp() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.busy || state.isUsingDefaultAppPath)
                }
            }
        }
    }

    private var supportPill: some View {
        switch state.supportStatus {
        case .supported:
            return AnyView(StatusPill(tone: .good, text: "此版本受支持", systemImage: "checkmark.seal.fill"))
        case .unsupported:
            return AnyView(StatusPill(tone: .warn, text: "暂不支持", systemImage: "exclamationmark.triangle.fill"))
        case .noWeChat:
            return AnyView(StatusPill(tone: .neutral, text: "未检测到微信", systemImage: "questionmark.circle"))
        case .failed:
            return AnyView(StatusPill(tone: .bad, text: "检测失败", systemImage: "exclamationmark.triangle.fill"))
        case .unknown:
            return AnyView(StatusPill(tone: .neutral, text: "检测中…"))
        }
    }

    // MARK: - Supported

    private var supportedActions: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionLabel(text: "撤回拦截方式")
                    Spacer()
                    installStatePill
                }

                HStack(spacing: 12) {
                    modeCard(
                        selected: !state.withTip,
                        icon: "eye.slash.fill",
                        title: "静默保留",
                        detail: "消息悄悄留下，界面上没有任何提示",
                        disabled: state.busy || !state.silentAvailable
                    ) {
                        if state.withTip { Task { await state.setWithTip(false) } }
                    }
                    modeCard(
                        selected: state.withTip,
                        icon: "eye.fill",
                        title: "显示撤回提示",
                        detail: "保留消息，并显示微信原生「撤回了一条消息」",
                        disabled: state.busy || !state.tipAvailable
                    ) {
                        if !state.withTip { Task { await state.setWithTip(true) } }
                    }
                }

                if !state.tipAvailable {
                    HintRow(systemImage: "info.circle",
                            text: "当前构建号暂不支持显示提示，只能用静默模式。", tint: .secondary)
                }

                if state.wechatRunning {
                    HStack(spacing: 10) {
                        HintRow(systemImage: "exclamationmark.circle.fill",
                                text: "安装前请先完全退出微信。", tint: .orange)
                        Button("退出微信") { Task { await state.quitWeChat() } }
                            .disabled(state.busy)
                    }
                }

                Button {
                    Task { await state.install(InstallRequest(withTip: state.withTip)) }
                } label: {
                    Text(state.installState == .installed
                         ? "重新安装防撤回"
                         : (state.withTip ? "开启防撤回（显示提示）" : "开启静默防撤回"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accent)
                .disabled(state.busy || state.wechatRunning || !state.silentAvailable)

                HStack(spacing: 12) {
                    Button("只检查，不修改") {
                        Task { await state.checkOnly(InstallRequest(withTip: state.withTip)) }
                    }
                    .buttonStyle(.link)
                    .disabled(state.busy || state.wechatRunning)
                }

                HintRow(systemImage: "info.circle",
                        text: "仅支持官网 dmg 版微信；App Store 版会被拒绝。安装会修改并重新签名微信，装完请完全退出并重开。")
            }
        }
    }

    private func modeCard(selected: Bool,
                          icon: String,
                          title: String,
                          detail: String,
                          disabled: Bool,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.accent : .secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? .primary : .secondary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Theme.accent.opacity(0.14) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Color.white.opacity(0.08),
                                  lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    private var installStatePill: some View {
        switch state.installState {
        case .installed:
            return AnyView(StatusPill(tone: .good,
                                      text: state.withTip ? "提示模式已开启" : "静默模式已开启",
                                      systemImage: "checkmark.circle.fill"))
        case .notInstalled: return AnyView(StatusPill(tone: .neutral, text: "未开启"))
        case .mismatch: return AnyView(StatusPill(tone: .warn, text: "数据不匹配"))
        case .unknown: return AnyView(EmptyView())
        }
    }

    // MARK: - Unsupported / no WeChat

    private var detectionFailedCard: some View {
        Card {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: "未能完成检测")
                    Text("请按上方提示处理后重新检测，或选择另一个官方微信 App。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("重新检测") { Task { await state.refresh() } }
                    .buttonStyle(.bordered)
                    .disabled(state.busy)
            }
        }
    }

    private func unsupportedCard(build: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "此版本暂不支持")
                Text("当前微信构建号 \(build) 不在本精简版支持的范围内。本工具仅支持 270390 / 270416 / 270601 的防撤回，不会拉取其他版本的补丁数据。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var noWeChatCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "未检测到微信")
                Text("没有在 \(state.appPath) 找到微信。请确认已安装 macOS 版微信 4。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("重新检测") { Task { await state.refresh() } }
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
