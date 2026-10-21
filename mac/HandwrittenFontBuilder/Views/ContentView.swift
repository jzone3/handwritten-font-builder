import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var project: Project

    var body: some View {
        HStack(spacing: 0) {
            GlyphGrid()
                .frame(width: 236)
            Divider()
            VStack(spacing: 0) {
                PadRepresentable(project: project)
                Divider()
                ControlBar()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                TextField("Font Name", text: $project.fontName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit { project.focusPad() }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Import Strokes…") { FileActions.importStrokes(into: project) }
                Button("Export Strokes…") { FileActions.exportStrokes(project) }
                Button("Open Website") { NSWorkspace.shared.open(Links.website) }
            }
        }
    }
}

/// Undo / Clear / Previous / Next plus the writing-mode switch and the trackpad activity light.
struct ControlBar: View {
    @EnvironmentObject private var project: Project

    var body: some View {
        HStack(spacing: 10) {
            if project.isWriting {
                Button("Stop Writing") { project.isWriting = false }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.black)
                    .keyboardShortcut(.escape, modifiers: [])
                Text("esc or click outside the box")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Click in the box, then write on the trackpad")
                    .font(.callout.weight(.medium))
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(project.trackpadActive ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                Text(project.touchCount == 0 ? "Trackpad: waiting for a touch" : "Trackpad touches: \(project.touchCount)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .help("Lights up while the trackpad is sending touches to the pad.")

            Spacer()

            Text("“\(String(project.current))”  \(project.currentIndex + 1) / \(GlyphSet.characters.count)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            shortcutButton("Undo", key: "⌘Z", action: project.undo).disabled(!project.canUndo)
            shortcutButton("Clear", key: "⌫", action: project.clear).disabled(project.currentStrokes.isEmpty)
            shortcutButton("Previous", key: "←", action: project.previous).disabled(project.currentIndex == 0)
            shortcutButton(project.currentStrokes.isEmpty ? "Skip" : "Next", key: "→", action: project.next)
                .disabled(project.currentIndex == GlyphSet.characters.count - 1)
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// A button with its key written on it, so the shortcuts are visible instead of hidden in tooltips.
    private func shortcutButton(_ title: String, key: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            project.focusPad()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                Text(key)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
