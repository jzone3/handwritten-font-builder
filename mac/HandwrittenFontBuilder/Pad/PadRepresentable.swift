import SwiftUI

/// Hosts `PadView` and wires it to the project: strokes in, finished strokes / key presses / touch activity out.
struct PadRepresentable: NSViewRepresentable {
    @ObservedObject var project: Project

    func makeNSView(context: Context) -> PadView {
        let view = PadView(frame: .zero)
        view.onStroke = { stroke in project.add(stroke) }
        view.onTouch = { aspect in project.noteTouch(deviceAspect: aspect) }
        view.onKey = { event in context.coordinator.handle(event, in: view) }
        view.onWritingModeChanged = { on in if project.isWriting != on { project.isWriting = on } }
        project.pad = view
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ view: PadView, context: Context) {
        view.strokes = project.currentStrokes
        view.label = project.current
        view.boxAspect = project.boxAspect
        if view.isWriting != project.isWriting { view.setWriting(project.isWriting) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(project: project) }

    @MainActor
    final class Coordinator {
        let project: Project
        init(project: Project) { self.project = project }

        /// Space / Return / → next, ← previous, ⌫ clears (when no stroke is in progress), Esc leaves writing mode,
        /// any character from the set jumps to that glyph.
        func handle(_ event: NSEvent, in view: PadView) -> Bool {
            if event.modifierFlags.intersection([.command, .control, .option]).isEmpty == false { return false }
            switch event.keyCode {
            case 49, 36, 76, 124: project.next(); return true          // space, return, enter, →
            case 123: project.previous(); return true                  // ←
            case 51, 117:                                              // delete, forward delete
                if !view.isStrokeInProgress { project.clear() }
                return true
            case 53: project.isWriting = false; return true            // esc
            default: break
            }
            if let chars = event.characters, chars.count == 1, let ch = chars.first, GlyphSet.index(of: ch) != nil {
                project.jump(to: ch)
                return true
            }
            return false
        }
    }
}
