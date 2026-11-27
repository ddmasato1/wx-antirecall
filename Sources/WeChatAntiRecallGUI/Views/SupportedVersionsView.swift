import SwiftUI

struct SupportedVersionRow: Identifiable {
    let build: String
    let wechatVersion: String
    let silent: Bool
    let tip: Bool
    var id: String { build }
}

/// Lists the builds bundled in patches.json. The WeChat version annotation comes from
/// the `wechatVersion` key that maintainers fill in per entry (the CLI ignores the
/// extra key, so the patch data stays the single source of truth).
struct SupportedVersionsView: View {
    @EnvironmentObject var state: AppState

    @State private var rows: [SupportedVersionRow] = []
    @State private var loadFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Card(padding: 16) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Theme.accentSoft)
                            .frame(width: 40, height: 40)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("内置离线支持列表")
                                .font(.system(size: 16, weight: .bold))
                            if !rows.isEmpty {
                                StatusPill(tone: .neutral, text: "共 \(rows.count) 个构建版本")
                            }
                        }
                        Text("仅对经过精确校验的微信构建号打补丁，全程离线运行，不联网拉取外部补丁数据。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if loadFailed {
                Card {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.amber)
                        Text("无法读取内置补丁数据（patches.json）。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(rows) { row in
                        rowCard(row)
                    }
                }
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        rows = Self.loadRows()
        loadFailed = rows.isEmpty
    }

    private static func loadRows() -> [SupportedVersionRow] {
        let url = BundledPaths.effectivePatchesJSON
        guard let data = try? Data(contentsOf: url),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array.compactMap { entry in
            guard let build = entry["version"] as? String else { return nil }
            let identifiers = ((entry["targets"] as? [[String: Any]]) ?? [])
                .compactMap { $0["identifier"] as? String }
            return SupportedVersionRow(
                build: build,
                wechatVersion: (entry["wechatVersion"] as? String) ?? "未知",
                silent: identifiers.contains("revoke"),
                tip: identifiers.contains("revoke-tip"))
        }
    }

    private func rowCard(_ row: SupportedVersionRow) -> some View {
        let installed = isInstalledBuild(row)
        return Card(padding: 15) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(installed ? Theme.accentSoft : Theme.surfaceSubtle)
                        .frame(width: 38, height: 38)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(installed ? Theme.accent : .secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("微信 \(row.wechatVersion)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        MonoChip(text: row.build, prefix: "Build")
                    }

                    HStack(spacing: 6) {
                        if row.silent {
                            capabilityTag(icon: "eye.slash.fill", text: "静默保留")
                        }
                        if row.tip {
                            capabilityTag(icon: "eye.fill", text: "撤回提示")
                        } else {
                            Text("仅支持静默模式")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer(minLength: 8)

                if installed {
                    StatusPill(tone: .good, text: "本机当前版本", systemImage: "checkmark.circle.fill")
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(installed ? Theme.accentBorder : .clear, lineWidth: 1.5)
        )
    }

    private func isInstalledBuild(_ row: SupportedVersionRow) -> Bool {
        state.displayBuild != "—" && state.displayBuild == row.build
    }

    private func capabilityTag(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .semibold))
            Text(text)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 7.5)
        .padding(.vertical, 3)
        .foregroundStyle(Theme.accent)
        .background(Capsule().fill(Theme.accentSoft))
    }
}
