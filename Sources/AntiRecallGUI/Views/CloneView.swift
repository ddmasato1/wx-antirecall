import SwiftUI
import AppKit

struct CloneView: View {
    @EnvironmentObject var state: AppState
    var onOpenHome: (() -> Void)? = nil

    @AppStorage("clone.enablePatch") private var enablePatchOnCreate = true
    @AppStorage("clone.withTip") private var cloneWithTip = false
    @State private var clonePendingDeletion: CloneInstanceInfo?
    @State private var showCreateConfirm = false

    private var canCreateClone: Bool {
        guard !state.busy else { return false }
        switch state.supportStatus {
        case .supported, .unsupported:
            return true
        case .noWeChat, .failed, .unknown:
            return false
        }
    }

    private var effectivePatchMode: String {
        guard state.supportStatus == .supported, enablePatchOnCreate else {
            return "none"
        }
        if cloneWithTip && state.tipAvailable {
            return "with-tip"
        }
        return "silent"
    }

    private var effectivePatchDescription: String {
        switch effectivePatchMode {
        case "with-tip": return "写入防撤回补丁（撤回提示）"
        case "silent": return "写入防撤回补丁（静默保留）"
        default: return "纯净无补丁"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let banner = state.banner {
                BannerView(banner: banner) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        state.banner = nil
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            createCloneCard
            cloneListCard
            cloneLifecycleGuideCard
        }
        .animation(.easeInOut(duration: 0.18), value: state.banner)
        .onAppear {
            if UserDefaults.standard.object(forKey: "clone.withTip") == nil {
                cloneWithTip = state.withTip
            }
        }
        .alert(
            "确认新建「微信 \(state.nextCloneIndex)」？",
            isPresented: $showCreateConfirm
        ) {
            Button("新建分身") {
                Task { await state.createClone(patchMode: effectivePatchMode) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将基于当前主微信生成 /Applications/WeChat \(state.nextCloneIndex).app（\(effectivePatchDescription)），不影响现有分身与聊天记录。")
        }
        .alert(
            "确认删除「\(clonePendingDeletion?.displayName ?? "微信分身")」？",
            isPresented: Binding(
                get: { clonePendingDeletion != nil },
                set: { if !$0 { clonePendingDeletion = nil } }
            ),
            presenting: clonePendingDeletion
        ) { target in
            Button("删除分身应用", role: .destructive) {
                clonePendingDeletion = nil
                Task { await state.removeClone(target) }
            }
            Button("取消", role: .cancel) {
                clonePendingDeletion = nil
            }
        } message: { target in
            Text("""
            仅移除客户端程序 \(target.path)，不会删除本地聊天记录与登录数据。

            聊天数据默认保留在：
            ~/Library/Containers/\(target.bundleIdentifier)
            如需彻底清理账号数据，可在删除后前往该目录手动移入废纸篓。
            """)
        }
    }

    // MARK: - Card 1: Create New Clone

    private var createCloneCard: some View {
        Card(padding: 15) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text("创建微信分身")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)

                            MonoChip(text: "微信 \(state.nextCloneIndex)")

                            if state.displayBuild != "—" {
                                Text("Build \(state.displayBuild)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Text("无需退出主微信，独立生成至 /Applications/WeChat \(state.nextCloneIndex).app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
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
                        Button {
                            if state.clones.isEmpty {
                                Task { await state.createClone(patchMode: effectivePatchMode) }
                            } else {
                                showCreateConfirm = true
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus.square.on.square")
                                    .font(.system(size: 11.5, weight: .semibold))
                                Text("新建分身")
                            }
                        }
                        .buttonStyle(CompactPrimaryPillButtonStyle())
                        .fixedSize(horizontal: true, vertical: false)
                        .disabled(!canCreateClone)
                    }
                }

                Rectangle()
                    .fill(Theme.subtleDivider)
                    .frame(height: 1)

                patchConfigurationSection
            }
        }
    }

    @ViewBuilder
    private var patchConfigurationSection: some View {
        switch state.supportStatus {
        case .supported:
            HStack(alignment: .center, spacing: 10) {
                Toggle(isOn: $enablePatchOnCreate) {
                    Text("写入防撤回补丁")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(state.busy)

                Spacer(minLength: 8)

                if enablePatchOnCreate {
                    CompactModeSegmentPicker(
                        withTip: $cloneWithTip,
                        tipAvailable: state.tipAvailable,
                        disabled: state.busy
                    )
                } else {
                    Text("纯净无补丁")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .unsupported(let build):
            HintRow(
                systemImage: "info.circle.fill",
                text: "当前主微信构建号（\(build)）暂未适配防撤回补丁，将以纯净模式创建多开分身。",
                tint: Theme.amber
            )

        case .noWeChat, .failed:
            HStack(spacing: 10) {
                HintRow(
                    systemImage: "exclamationmark.triangle.fill",
                    text: "未检测到可用的官方主微信，请先前往「首页」确认官方微信路径。",
                    tint: Theme.danger
                )
                if let onOpenHome {
                    Button("前往首页") {
                        onOpenHome()
                    }
                    .buttonStyle(SecondaryPillButtonStyle(compact: true))
                }
            }

        case .unknown:
            HintRow(
                systemImage: "hourglass",
                text: "正在读取主微信版本信息…",
                tint: .secondary
            )
        }
    }

    // MARK: - Card 2: Existing Clones List

    private var cloneListCard: some View {
        Card(padding: 15) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 7) {
                            Text("已创建的分身")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                            StatusPill(tone: .neutral, text: "\(state.clones.count) 个")
                        }
                        Text("Dock 与菜单栏显示独立中文名，互不抢占通知")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    IconCircleButton(
                        systemImage: "arrow.clockwise",
                        helpText: "刷新分身列表",
                        disabled: state.busy
                    ) {
                        Task { await state.refreshClones() }
                    }
                }

                if state.clones.isEmpty {
                    emptyClonesPlaceholder
                } else {
                    VStack(spacing: 8) {
                        ForEach(state.clones) { clone in
                            CloneRowView(
                                clone: clone,
                                mainBuild: state.displayBuild,
                                canRebuild: canCreateClone,
                                busy: state.busy,
                                onLaunch: { Task { await state.launchClone(clone) } },
                                onQuit: { Task { await state.quitClone(clone) } },
                                onRebuild: {
                                    Task { await state.rebuildClone(clone, patchMode: effectivePatchMode) }
                                },
                                onDelete: { clonePendingDeletion = clone }
                            )
                        }
                    }
                }
            }
        }
    }

    private var emptyClonesPlaceholder: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.accentSoft)
                    .frame(width: 34, height: 34)
                Image(systemName: "square.on.square")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("尚未创建多开分身")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("点击右上角「新建分身」即可一键生成独立分身应用，多账号聊天数据彼此独立。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                .fill(Theme.surfaceSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    // MARK: - Card 3: Rebuild & Cleanup Guide

    private var cloneLifecycleGuideCard: some View {
        Card(padding: 15) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    SectionLabel(
                        text: "更新与清理说明",
                        subtitle: "分身升级同步、卸载流程与本地数据位置"
                    )

                    Spacer(minLength: 8)

                    Button {
                        let containersURL = FileManager.default.homeDirectoryForCurrentUser
                            .appendingPathComponent("Library/Containers", isDirectory: true)
                        NSWorkspace.shared.open(containersURL)
                    } label: {
                        Label("打开数据目录", systemImage: "folder")
                    }
                    .buttonStyle(SecondaryPillButtonStyle(compact: true))
                    .help("在访达中打开 ~/Library/Containers 目录")
                }

                guideRow(
                    icon: "arrow.triangle.2.circlepath.circle.fill",
                    tint: Theme.accent,
                    title: "升级与切换模式",
                    detail: "主微信升级后，先点分身右侧「退出」再点「同步重建」即可无损更新，聊天记录自动保留。"
                )

                Rectangle()
                    .fill(Theme.subtleDivider)
                    .frame(height: 1)

                guideRow(
                    icon: "trash.circle.fill",
                    tint: Theme.amber,
                    title: "删除与数据清理",
                    detail: "先点「退出」解锁「删除」；删除仅移除客户端包，如需彻底清除账号数据，请点击右上角打开 Containers 目录并移除对应 cloneN 文件夹。"
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

// MARK: - Subcomponents

private struct CloneRowView: View {
    let clone: CloneInstanceInfo
    let mainBuild: String
    let canRebuild: Bool
    let busy: Bool
    let onLaunch: () -> Void
    let onQuit: () -> Void
    let onRebuild: () -> Void
    let onDelete: () -> Void

    private var icon: NSImage {
        let image = NSWorkspace.shared.icon(forFile: clone.path)
        image.size = NSSize(width: 96, height: 96)
        return image
    }

    private var hasUpgradeAvailable: Bool {
        mainBuild != "—" && clone.installedBuild != mainBuild
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(clone.displayName)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(.primary)

                    if clone.isRunning {
                        StatusPill(tone: .good, text: "运行中", systemImage: "circle.fill")
                    } else {
                        StatusPill(tone: .neutral, text: "未运行")
                    }

                    if hasUpgradeAvailable {
                        StatusPill(tone: .warn, text: "可同步升级", systemImage: "arrow.up.circle.fill")
                    }
                }

                HStack(spacing: 6) {
                    MonoChip(text: clone.installedBuild, prefix: "Build")
                    patchStateBadge
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                if clone.isRunning {
                    Button("退出", action: onQuit)
                        .buttonStyle(SecondaryPillButtonStyle(compact: true))
                        .disabled(busy)
                        .help("退出正在运行的「微信 \(clone.index)」")
                } else {
                    Button("启动", action: onLaunch)
                        .buttonStyle(SecondaryPillButtonStyle(compact: true))
                        .disabled(busy)
                        .help("启动 \(clone.path)")
                }

                Button("同步重建", action: onRebuild)
                    .buttonStyle(SecondaryPillButtonStyle(compact: true))
                    .disabled(busy || clone.isRunning || !canRebuild)
                    .help(clone.isRunning
                          ? "请先退出该分身后再执行同步重建"
                          : "使用当前主微信与上方所选补丁设置覆盖更新此分身")

                Button(action: onDelete) {
                    Text("删除")
                        .foregroundStyle(clone.isRunning || busy ? Color.secondary.opacity(0.45) : Theme.danger)
                }
                .buttonStyle(SecondaryPillButtonStyle(compact: true))
                .disabled(busy || clone.isRunning)
                .help(clone.isRunning ? "请先退出该分身后再删除" : "删除「\(clone.displayName)」应用程序包")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Theme.surfaceSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var patchStateBadge: some View {
        switch clone.patchState {
        case .silent:
            StatusPill(tone: .good, text: "静默防撤回", systemImage: "eye.slash.fill")
        case .withTip:
            StatusPill(tone: .good, text: "提示防撤回", systemImage: "eye.fill")
        case .none:
            StatusPill(tone: .neutral, text: "未开启补丁")
        case .unsupported:
            StatusPill(tone: .neutral, text: "版本未适配")
        case .mismatch:
            StatusPill(tone: .warn, text: "补丁异常", systemImage: "exclamationmark.circle")
        }
    }
}
