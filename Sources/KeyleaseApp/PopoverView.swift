import SwiftUI
import AppKit

struct PopoverView: View {
    @ObservedObject var store: LeaseStore

    var body: some View {
        Group {
            if store.isActive {
                activeView
            } else {
                setupView
            }
        }
        .padding(14)
        .frame(width: 340, height: 240)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .foregroundStyle(.blue)
                Text("临时通道")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }

            Text("默认 10 分钟 · 一次使用")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                pasteAndActivate()
            } label: {
                Label("从剪贴板开启通道", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("先把密钥复制到剪贴板，再点这个按钮。通道到期自动关闭。")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            Text("Agent 用 keylease run --env <变量名> -- <命令> 调用；密钥只进子进程环境，不落盘。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var activeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .foregroundStyle(.green)
                Text("通道已开启")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }

            Text("变量名由 Agent 指定")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("一次性 · \(format(remainingSeconds(at: context.date)))")
                    .font(.system(.body, design: .monospaced))
            }

            Divider()

            HStack {
                Button("从剪贴板替换") {
                    pasteAndActivate()
                }
                Spacer()
                Button("关闭通道", role: .destructive) {
                    store.revoke()
                }
            }

            Text("Agent 用 keylease run --env <变量名> -- <命令> 调用")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("App 退出、到期或使用后，通道立即关闭。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func pasteAndActivate() {
        guard let raw = NSPasteboard.general.string(forType: .string) else {
            NSSound.beep()
            return
        }

        let secret = raw.trimmingCharacters(in: .newlines)
        guard !secret.isEmpty else {
            NSSound.beep()
            return
        }

        store.activate(secret: secret)
    }

    private func remainingSeconds(at date: Date) -> Int {
        guard let expiresAt = store.expiresAt else { return 0 }
        return max(0, Int(expiresAt.timeIntervalSince(date)))
    }

    private func format(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
