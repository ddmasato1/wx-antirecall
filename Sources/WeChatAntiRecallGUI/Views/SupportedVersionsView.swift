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
        Card {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 7) {
                            Text("内置离线支持列表")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)

                            if !rows.isEmpty {
                                StatusPill(tone: .neutral, text: "\(rows.count) 个构建")
                            }
                        }

                        Text("仅对精确校验的官网 DMG 版构建号打补丁，全程离线运行")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                Rectangle()
                    .fill(Theme.subtleDivider)
                    .frame(height: 1)

                if loadFailed {
                    HintRow(
                        systemImage: "exclamationmark.triangle.fill",
                        text: "无法读取内置补丁数据（patches.json）。",
                        tint: Theme.amber
                    )
                } else {
                    VStack(spacing: 8) {
                        ForEach(rows) { row in
                            versionRow(row)
                        }
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

    private func versionRow(_ row: SupportedVersionRow) -> some View {
        let installed = isInstalledBuild(row)
        return HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 7) {
                Text("微信 \(row.wechatVersion)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                MonoChip(text: row.build, prefix: "Build")
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                if row.silent {
                    capabilityTag(icon: "eye.slash.fill", text: "静默保留")
                }

                if row.tip {
                    capabilityTag(icon: "eye.fill", text: "撤回提示")
                } else {
                    Text("仅静默")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                }

                if installed {
                    StatusPill(tone: .good, text: "当前版本", systemImage: "checkmark.circle.fill")
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Theme.surfaceSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(installed ? Theme.accentBorder : Theme.border, lineWidth: installed ? 1.2 : 1)
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
