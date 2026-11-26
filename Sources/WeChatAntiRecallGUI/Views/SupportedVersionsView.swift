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
            Text("支持的版本").font(.title2.weight(.semibold))
            Text("本精简版只为以下微信构建号内置补丁数据，不会从网络拉取其他版本的补丁。")
                .font(.callout)
                .foregroundStyle(.secondary)

            if loadFailed {
                Card {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("无法读取内置补丁数据（patches.json）。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }

            ForEach(rows) { row in
                rowCard(row)
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
        return Card {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.title3)
                    .foregroundStyle(installed ? Theme.accent : Color.secondary.opacity(0.6))
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("微信 \(row.wechatVersion)")
                            .font(.body.weight(.semibold))
                        Text("-")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        MonoChip(text: row.build)
                    }
                    HStack(spacing: 6) {
                        if row.silent { modeTag("静默防撤回") }
                        if row.tip { modeTag("显示撤回提示") }
                    }
                }
                Spacer()
                if installed {
                    StatusPill(tone: .good, text: "当前安装", systemImage: "checkmark.circle.fill")
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(installed ? Theme.accent.opacity(0.45) : .clear, lineWidth: 1)
        )
    }

    private func isInstalledBuild(_ row: SupportedVersionRow) -> Bool {
        state.displayBuild != "—" && state.displayBuild == row.build
    }

    private func modeTag(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.accent.opacity(0.14)))
            .foregroundStyle(Theme.accent)
    }
}
