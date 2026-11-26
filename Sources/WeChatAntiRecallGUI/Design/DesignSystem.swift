import SwiftUI

enum Theme {
    // Brand teal — taken from the app icon's rotating arrow.
    static let accent = Color(red: 0.055, green: 0.68, blue: 0.49)
    static let accentBright = Color(red: 0.10, green: 0.80, blue: 0.58)
    static let corner: CGFloat = 16
    static let cardPadding: CGFloat = 20
    static let gap: CGFloat = 14

    // Charcoal surfaces matching the icon background. The whole window is
    // dark-branded (preferredColorScheme(.dark) in ContentView).
    static let sidebar = Color(red: 0.125, green: 0.14, blue: 0.15)
    static let surface = Color(red: 0.15, green: 0.165, blue: 0.175)
    static let surfaceStroke = Color.white.opacity(0.07)
    static let chipBackground = Color.white.opacity(0.08)
}

// A dark, quiet card surface.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Theme.surfaceStroke, lineWidth: 1)
            )
    }
}

// A monospaced capsule for build numbers and other technical values.
struct MonoChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.monospaced().weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.chipBackground))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }
}

struct StatusPill: View {
    enum Tone { case good, bad, warn, neutral }
    let tone: Tone
    let text: String
    var systemImage: String?

    private var color: Color {
        switch tone {
        case .good: return Theme.accent
        case .bad: return .red
        case .warn: return .orange
        case .neutral: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage).font(.caption2.weight(.bold))
            }
            Text(text).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(color)
        .background(Capsule().fill(color.opacity(0.16)))
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String
    var mono: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(mono ? .body.monospaced() : .body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}

// A quiet inline hint line with an icon.
struct HintRow: View {
    let systemImage: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

struct BannerView: View {
    let banner: Banner
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
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(banner.title).font(.subheadline.weight(.semibold))
                Text(banner.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let settingsURL = banner.settingsURL, let url = URL(string: settingsURL) {
                    Button(banner.settingsButtonTitle) { openURL(url) }
                        .buttonStyle(.borderedProminent)
                        .tint(color)
                        .controlSize(.small)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(color.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(color.opacity(0.25), lineWidth: 1)
        )
    }
}
