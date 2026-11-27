import SwiftUI
import AppKit

enum NavSection: String, CaseIterable, Identifiable {
    case home
    case clone
    case versions
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "首页"
        case .clone: return "微信多开"
        case .versions: return "支持版本"
        case .permissions: return "权限帮助"
        }
    }

    var icon: String {
        switch self {
        case .home: return "shield.lefthalf.filled"
        case .clone: return "square.on.square"
        case .versions: return "checkmark.seal"
        case .permissions: return "lock.shield"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @SceneStorage("navigation.section") private var selectedSectionRaw = NavSection.home.rawValue
    @Namespace private var navAnimation

    private var selectedSection: NavSection {
        NavSection(rawValue: selectedSectionRaw) ?? .home
    }

    private func select(_ section: NavSection) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            selectedSectionRaw = section.rawValue
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Layered adaptive canvas with subtle top emerald ambient glow
            Theme.canvas
                .ignoresSafeArea()

            RadialGradient(
                colors: [Theme.canvasTopGlow, .clear],
                center: .top,
                startRadius: 10,
                endRadius: 340
            )
            .frame(height: 320)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topNavigationBar

                Rectangle()
                    .fill(Theme.subtleDivider)
                    .frame(height: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.gap) {
                        switch selectedSection {
                        case .home:
                            HomeView(onOpenVersions: { select(.versions) })
                        case .clone:
                            CloneView(onOpenHome: { select(.home) })
                        case .versions:
                            SupportedVersionsView()
                        case .permissions:
                            PermissionsView()
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 22)
                    .frame(maxWidth: 620, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)
                }

                LogDrawer()
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .tint(Theme.accent)
        .onAppear { state.onAppear() }
    }

    // MARK: - Unified Top Titlebar & Segmented Pill Navigation

    private var topNavigationBar: some View {
        HStack(spacing: 0) {
            // Reserve leading clearance for macOS window traffic lights
            Color.clear
                .frame(width: 76, height: 1)

            Spacer(minLength: 8)

            // Segmented pill tabs
            HStack(spacing: 2) {
                ForEach(NavSection.allCases) { section in
                    let isSelected = (selectedSection == section)
                    Button {
                        select(section)
                    } label: {
                        HStack(spacing: 4.5) {
                            Image(systemName: section.icon)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? Theme.accent : .secondary)
                            Text(section.title)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .lineLimit(1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5.5)
                        .background(
                            ZStack {
                                if isSelected {
                                    Capsule()
                                        .fill(Theme.pillThumb)
                                        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(Theme.border, lineWidth: 0.8)
                                        )
                                        .matchedGeometryEffect(id: "activeNavPill", in: navAnimation)
                                }
                            }
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                Capsule()
                    .fill(Theme.pillTrack)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Theme.border, lineWidth: 0.8)
            )

            Spacer(minLength: 8)

            WeChatRunningPill()
                .fixedSize(horizontal: true, vertical: false)
                .padding(.trailing, 16)
        }
        .padding(.top, 7)
        .padding(.bottom, 9)
    }
}

struct WeChatRunningPill: View {
    @EnvironmentObject var state: AppState
    @State private var isHovered = false

    var body: some View {
        Group {
            if state.wechatRunning {
                Button {
                    Task { await state.quitWeChat() }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Theme.amber)
                            .frame(width: 7, height: 7)
                        Text(isHovered ? "点击退出微信" : "微信运行中")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(isHovered ? Theme.amber : .secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Theme.amber.opacity(isHovered ? 0.16 : 0.10))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Theme.amber.opacity(0.28), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(state.busy)
                .help("安装前需退出微信，点击可立即退出")
                .onHover { isHovered = $0 }
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 7, height: 7)
                    Text("微信未运行")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Theme.pillTrack)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Theme.border, lineWidth: 0.8)
                )
            }
        }
    }
}
