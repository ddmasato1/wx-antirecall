import SwiftUI
import AppKit

// MARK: - Adaptive Design Tokens

enum Theme {
    private static func dynamic(
        light: (CGFloat, CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: c.3)
        })
    }

    // Brand Emerald
    static let accent = dynamic(
        light: (0.027, 0.706, 0.365, 1.0),   // #07B45D
        dark:  (0.110, 0.820, 0.475, 1.0)    // #1CD179
    )
    static let accentDeep = dynamic(
        light: (0.020, 0.588, 0.310, 1.0),   // #05964F
        dark:  (0.043, 0.678, 0.388, 1.0)    // #0BAD63
    )
    static let accentSoft = dynamic(
        light: (0.027, 0.706, 0.365, 0.11),
        dark:  (0.110, 0.820, 0.475, 0.15)
    )
    static let accentBorder = dynamic(
        light: (0.027, 0.706, 0.365, 0.38),
        dark:  (0.110, 0.820, 0.475, 0.45)
    )

    // Semantic Tones
    static let amber = dynamic(
        light: (0.855, 0.490, 0.020, 1.0),
        dark:  (0.980, 0.675, 0.180, 1.0)
    )
    static let amberDeep = dynamic(
        light: (0.760, 0.400, 0.010, 1.0),
        dark:  (0.880, 0.530, 0.080, 1.0)
    )
    static let danger = dynamic(
        light: (0.860, 0.210, 0.210, 1.0),
        dark:  (0.980, 0.380, 0.380, 1.0)
    )
    static let info = dynamic(
        light: (0.090, 0.460, 0.850, 1.0),
        dark:  (0.320, 0.650, 0.980, 1.0)
    )

    // Layered Surfaces
    static let canvas = dynamic(
        light: (0.953, 0.961, 0.973, 1.0),   // #F3F5F8
        dark:  (0.075, 0.082, 0.094, 1.0)    // #131518
    )
    static let canvasTopGlow = dynamic(
        light: (0.027, 0.706, 0.365, 0.06),
        dark:  (0.110, 0.820, 0.475, 0.09)
    )
    static let surface = dynamic(
        light: (1.000, 1.000, 1.000, 1.0),   // #FFFFFF
        dark:  (0.114, 0.125, 0.141, 1.0)    // #1D2024
    )
    static let surfaceSubtle = dynamic(
        light: (0.961, 0.969, 0.980, 1.0),   // #F5F7FA
        dark:  (0.149, 0.165, 0.184, 1.0)    // #262A2F
    )
    static let surfaceHover = dynamic(
        light: (0.925, 0.937, 0.953, 1.0),
        dark:  (0.188, 0.208, 0.231, 1.0)
    )
    static let border = dynamic(
        light: (0.040, 0.080, 0.140, 0.075),
        dark:  (1.000, 1.000, 1.000, 0.085)
    )
    static let subtleDivider = dynamic(
        light: (0.040, 0.080, 0.140, 0.06),
        dark:  (1.000, 1.000, 1.000, 0.07)
    )
    static let cardShadow = dynamic(
        light: (0.040, 0.080, 0.150, 0.05),
        dark:  (0.000, 0.000, 0.000, 0.28)
    )

    // Top Navigation Pill Track & Thumb
    static let pillTrack = dynamic(
        light: (0.040, 0.080, 0.140, 0.06),
        dark:  (1.000, 1.000, 1.000, 0.075)
    )
    static let pillThumb = dynamic(
        light: (1.000, 1.000, 1.000, 1.0),
        dark:  (0.204, 0.224, 0.251, 1.0)
    )

    // Layout Metrics
    static let corner: CGFloat = 16
    static let innerCorner: CGFloat = 11
    static let cardPadding: CGFloat = 18
    static let gap: CGFloat = 14
}

// MARK: - Window Appearance Configurator

struct WindowConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.configure(window: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            context.coordinator.configure(window: window)
        }
    }

    final class Coordinator {
        private var didInitialResize = false

        func configure(window: NSWindow) {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = false

            if !didInitialResize {
                didInitialResize = true
                let targetSize = NSSize(width: 580, height: 680)
                // Reset oversized legacy frames (e.g. previous 860px dual-column window)
                if window.frame.width > 680 || window.frame.height < 620 {
                    let oldCenter = NSPoint(x: window.frame.midX, y: window.frame.midY)
                    let newOrigin = NSPoint(
                        x: round(oldCenter.x - targetSize.width * 0.5),
                        y: round(oldCenter.y - targetSize.height * 0.5)
                    )
                    window.setFrame(NSRect(origin: newOrigin, size: targetSize), display: true, animate: false)
                }
            }
        }
    }
}

// MARK: - Elevated Card Surface

struct Card<Content: View>: View {
    var padding: CGFloat = Theme.cardPadding
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.surface)
                    .shadow(color: Theme.cardShadow, radius: 10, x: 0, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}

// MARK: - Chips & Status Pills

struct MonoChip: View {
    let text: String
    var prefix: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let prefix {
                Text(prefix)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            Text(text)
                .font(.caption.monospaced().weight(.medium))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(
            Capsule()
                .fill(Theme.surfaceSubtle)
        )
        .overlay(
            Capsule()
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }
}

struct StatusPill: View {
    enum Tone { case good, bad, warn, neutral }
    let tone: Tone
    let text: String
    var systemImage: String? = nil

    private var color: Color {
        switch tone {
        case .good: return Theme.accent
        case .bad: return Theme.danger
        case .warn: return Theme.amber
        case .neutral: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(color)
        .background(
            Capsule().fill(color.opacity(tone == .neutral ? 0.10 : 0.13))
        )
        .overlay(
            Capsule().strokeBorder(color.opacity(tone == .neutral ? 0.14 : 0.24), lineWidth: 1)
        )
    }
}

// MARK: - Unified Button Styles

struct PrimaryActionButtonStyle: ButtonStyle {
    enum Variant {
        case emerald
        case amber
    }

    var variant: Variant = .emerald
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    private var topColor: Color {
        variant == .emerald ? Theme.accent : Theme.amber
    }

    private var bottomColor: Color {
        variant == .emerald ? Theme.accentDeep : Theme.amberDeep
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .padding(.horizontal, 16)
            .background(
                Group {
                    if isEnabled {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [topColor, bottomColor],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .brightness(isHovered ? 0.04 : 0)
                            .shadow(color: topColor.opacity(0.28), radius: 8, x: 0, y: 3)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.surfaceSubtle)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isEnabled ? Color.white.opacity(0.22) : Theme.border,
                        lineWidth: 1
                    )
            )
            .scaleEffect(configuration.isPressed && isEnabled ? 0.988 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

struct SecondaryPillButtonStyle: ButtonStyle {
    var compact: Bool = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.55))
            .padding(.horizontal, compact ? 10 : 13)
            .padding(.vertical, compact ? 5 : 6.5)
            .background(
                RoundedRectangle(cornerRadius: compact ? 8 : 9, style: .continuous)
                    .fill(isHovered && isEnabled ? Theme.surfaceHover : Theme.surfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 8 : 9, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

struct IconCircleButton: View {
    let systemImage: String
    var helpText: String = ""
    var disabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(disabled ? Color.secondary.opacity(0.45) : .secondary)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(isHovered && !disabled ? Theme.surfaceHover : Theme.surfaceSubtle)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(helpText)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Typography & Inline Hints

struct SectionLabel: View {
    let text: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct HintRow: View {
    let systemImage: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 14, alignment: .center)
                .padding(.top, 1)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Alert / Result Banner

struct BannerView: View {
    let banner: Banner
    var onDismiss: (() -> Void)? = nil
    @Environment(\.openURL) private var openURL

    private var icon: String {
        switch banner.kind {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var color: Color {
        switch banner.kind {
        case .success: return Theme.accent
        case .error: return Theme.danger
        case .warning: return Theme.amber
        case .info: return Theme.info
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(banner.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(banner.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let settingsURL = banner.settingsURL, let url = URL(string: settingsURL) {
                    Button {
                        openURL(url)
                    } label: {
                        Label(banner.settingsButtonTitle, systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(SecondaryPillButtonStyle(compact: true))
                    .padding(.top, 4)
                }
            }

            Spacer(minLength: 0)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(color.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: Theme.cardShadow, radius: 8, x: 0, y: 2)
        )
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(color.opacity(0.28), lineWidth: 1)
        )
    }
}
