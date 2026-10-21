import SwiftUI

/// Where the strokes file goes to become a font. The parent/website owner sets the final domain here.
enum Links {
    static let website = URL(string: "https://handwritten-font-builder.vercel.app")!
    static let repo = URL(string: "https://github.com/jzone3/handwritten-font-builder")!
    static let author = URL(string: "https://x.com/imjaredz")!
    static let devin = URL(string: "https://devin.ai")!
}

@main
struct HandwrittenFontBuilderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var project = Project.shared

    var body: some Scene {
        Window("Handwritten Font Builder", id: "main") {
            ContentView()
                .environmentObject(project)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1060, height: 680)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Handwritten Font Builder") { About.show() }
            }
            CommandGroup(replacing: .newItem) {
                Button("New") { FileActions.newProject(project) }.keyboardShortcut("n")
                Divider()
                Button("Import Strokes…") { FileActions.importStrokes(into: project) }.keyboardShortcut("i")
                Button("Export Strokes…") { FileActions.exportStrokes(project) }.keyboardShortcut("e")
                Divider()
                Button("Open Website") { NSWorkspace.shared.open(Links.website) }
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo Stroke") { project.undo() }.keyboardShortcut("z").disabled(!project.canUndo)
                Button("Clear Glyph") { project.clear() }.keyboardShortcut(.delete).disabled(project.currentStrokes.isEmpty)
            }
            CommandMenu("Glyph") {
                Button("Previous Glyph") { project.previous() }.keyboardShortcut("[")
                Button("Next Glyph") { project.next() }.keyboardShortcut("]")
                Divider()
                Button(project.isWriting ? "Stop Writing" : "Write with Trackpad") { project.isWriting.toggle() }
                    .keyboardShortcut("t")
                #if DEBUG
                Divider()
                Button("Simulate Trackpad Stroke (Debug)") { project.pad?.simulateStroke() }.keyboardShortcut("t", modifiers: [.command, .shift])
                #endif
            }
            CommandGroup(replacing: .help) {
                Button("Handwritten Font Builder Website") { NSWorkspace.shared.open(Links.website) }
                Button("Source Code") { NSWorkspace.shared.open(Links.repo) }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        DispatchQueue.main.async { Welcome.showIfNeeded() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        Project.shared.pad?.exitWritingMode()
        Project.shared.saveNow()
    }
}
