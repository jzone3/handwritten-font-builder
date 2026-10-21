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
            Button(project.isWriting ? "Stop Writing (esc)" : "Write with Trackpad") {
                project.isWriting.toggle()
                project.focusPad()
            }
            .buttonStyle(.borderedProminent)
            .tint(project.isWriting ? Color.black : Color.accentColor)
            .help("Hides the cursor and parks it over the pad so your finger can write anywhere on the trackpad. Esc or ⌘T to stop.")

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

            Button("Undo") { act { project.undo() } }.disabled(!project.canUndo).help("⌘Z")
            Button("Clear") { act { project.clear() } }.disabled(project.currentStrokes.isEmpty).help("⌫")
            Button("Previous") { act { project.previous() } }.disabled(project.currentIndex == 0).help("←")
            Button(project.currentStrokes.isEmpty ? "Skip" : "Next") { act { project.next() } }
                .disabled(project.currentIndex == GlyphSet.characters.count - 1)
                .help("Space, Return or →")
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func act(_ body: () -> Void) {
        body()
        project.focusPad()
    }
}
