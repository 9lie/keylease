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
        .frame(width: 340, height: 220)
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
                Text("Temporary channel")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }

            Text("10 min · single use")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                pasteAndActivate()
            } label: {
                Label("Open from clipboard", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Copy the secret, then press ⌘V or click above.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            Text("Agent: keylease run --env NAME -- <command>")
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
                Text("Channel open")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }

            Text("Agent chooses the variable name")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("Single use · \(format(remainingSeconds(at: context.date)))")
                    .font(.system(.body, design: .monospaced))
            }

            Divider()

            HStack {
                Button("Replace from clipboard") {
                    pasteAndActivate()
                }
                Spacer()
                Button("Close channel", role: .destructive) {
                    store.revoke()
                }
            }

            Text("keylease run --env NAME -- <command>")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("Closes on use, expiry, or app exit.")
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
