import SwiftUI
import AppKit

struct LogDrawer: View {
    @EnvironmentObject var state: AppState
    @State private var expanded = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.subtleDivider)
                .frame(height: 1)

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "shield.checkered")
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)
                    Text("微信防撤回 · 本地离线补丁工具")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if expanded && !state.logLines.isEmpty {
                    Button {
                        copyLogs()
                    } label: {
                        Text(copied ? "已复制" : "复制")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(copied ? Theme.accent : .secondary)
                    }
                    .buttonStyle(.plain)

                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Button("清空") {
                        state.clearLog()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        expanded.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "terminal")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("运行日志")
                            .font(.caption.weight(.medium))
                        if !state.logLines.isEmpty {
                            Text("\(state.logLines.count)")
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Theme.accentSoft))
                                .foregroundStyle(Theme.accent)
                        }
                        Image(systemName: expanded ? "chevron.down" : "chevron.up")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Theme.surfaceSubtle)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Theme.border, lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 7)

            if expanded {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            if state.logLines.isEmpty {
                                Text("暂无运行日志。执行补丁检查或安装后将在此显示详细输出。")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .padding(.vertical, 8)
                            }
                            ForEach(Array(state.logLines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                        .padding(12)
                    }
                    .frame(height: 145)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.surfaceSubtle)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
                    .onChange(of: state.logLines.count) { _ in
                        if let last = state.logLines.indices.last {
                            withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                        }
                    }
                }
            }
        }
        .background(Theme.surface.opacity(0.85))
    }

    private func copyLogs() {
        let text = state.logLines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}
