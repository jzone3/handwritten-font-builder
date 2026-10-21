import AppKit
import UniformTypeIdentifiers

/// New / Import / Export, all on the main window with stock panels and sheets.
@MainActor
enum FileActions {
    private static var window: NSWindow? { NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible } }

    static func newProject(_ project: Project) {
        guard project.drawnCount > 0 else { project.reset(); return }
        let alert = NSAlert()
        alert.messageText = "Start a new project?"
        alert.informativeText = "All \(project.drawnCount) drawn glyphs will be cleared. Export first if you want to keep them."
        alert.addButton(withTitle: "New Project")
        alert.addButton(withTitle: "Cancel")
        present(alert) { response in
            if response == .alertFirstButtonReturn { project.reset() }
        }
    }

    static func importStrokes(into project: Project) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a .strokes.json file saved by this app or by the website."
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let contents = try StrokeFile.decode(try Data(contentsOf: url))
                project.replace(with: contents)
                if let first = GlyphSet.characters.firstIndex(where: { contents.glyphs[$0] == nil }) { project.currentIndex = first }
            } catch {
                let alert = NSAlert()
                alert.messageText = "Couldn’t import “\(url.lastPathComponent)”"
                alert.informativeText = error.localizedDescription
                present(alert, completion: nil)
            }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: handler) } else { handler(panel.runModal()) }
    }

    static func exportStrokes(_ project: Project) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let name = project.fontName.trimmingCharacters(in: .whitespacesAndNewlines)
        panel.nameFieldStringValue = "\(name.isEmpty ? Project.defaultFontName : name).\(StrokeFile.fileExtension)"
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try StrokeFile.encode(project.contents).write(to: url, options: .atomic)
                showExported(url)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Couldn’t export"
                alert.informativeText = error.localizedDescription
                present(alert, completion: nil)
            }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: handler) } else { handler(panel.runModal()) }
    }

    private static func showExported(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = "Strokes exported"
        alert.informativeText = "Now open the website and drop this file in to build your font.\n\n\(url.lastPathComponent)"
        alert.addButton(withTitle: "Open Website")
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "Done")
        present(alert) { response in
            switch response {
            case .alertFirstButtonReturn: NSWorkspace.shared.open(Links.website)
            case .alertSecondButtonReturn: NSWorkspace.shared.activateFileViewerSelecting([url])
            default: break
            }
        }
    }

    /// Sheet on the main window when there is one (a panel's completion handler runs before the panel is gone, so wait a turn).
    private static func present(_ alert: NSAlert, completion: ((NSApplication.ModalResponse) -> Void)?) {
        DispatchQueue.main.async {
            if let window, window.attachedSheet == nil {
                alert.beginSheetModal(for: window) { completion?($0) }
            } else {
                completion?(alert.runModal())
            }
        }
    }
}
