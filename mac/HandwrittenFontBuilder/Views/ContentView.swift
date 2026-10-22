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
                Button("Your Font…") { project.showingFont = true }
                    .help("Preview, download, publish and share the font (⌘⏎)")
            }
        }
        .sheet(isPresented: $project.showingFont) {
            FontSheet()
                .environmentObject(project)
        }
    }
}

/// Trackpad-mode switch (bottom-left), the trackpad activity light, New, and Undo / Clear / Previous / Next (Finish on the last glyph).
struct ControlBar: View {
    @EnvironmentObject private var project: Project

    var body: some View {
        HStack(spacing: 10) {
            if project.isWriting {
                shortcutButton("Exit Trackpad Mode", key: "esc") { project.isWriting = false }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.black)
                    .keyboardShortcut(.escape, modifiers: [])
                Text("Write on the trackpad with one finger")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                shortcutButton("Enter Trackpad Mode", key: "⌘T") { project.isWriting = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.black)
                Text("Mouse mode: click and drag in the box to draw")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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

            shortcutButton("New", key: "⌘N") { FileActions.newProject(project) }
                .help("Clear every glyph and start a new project")
            shortcutButton("Undo", key: "⌘Z", action: project.undo).disabled(!project.canUndo)
            shortcutButton("Clear", key: "⌫", action: project.clear).disabled(project.currentStrokes.isEmpty)
            shortcutButton("Previous", key: "←", action: project.previous).disabled(project.currentIndex == 0)
            if project.isOnLastGlyph {
                shortcutButton("Finish", key: "→", action: project.next)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.black)
                    .help("Open your font: preview, download, publish, share")
            } else {
                shortcutButton(project.currentStrokes.isEmpty ? "Skip" : "Next", key: "→", action: project.next)
            }
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
                    .opacity(0.6)
            }
        }
    }
}
