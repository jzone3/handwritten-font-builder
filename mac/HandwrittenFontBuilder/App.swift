import SwiftUI

/// Where the strokes file goes to become a font. The parent/website owner sets the final domain here.
enum Links {
    /// `defaults write com.jzone3.HandwrittenFontBuilder websiteBase https://…` points the app at a preview deploy.
    static let website = URL(string: UserDefaults.standard.string(forKey: "websiteBase") ?? "") ?? URL(string: "https://buildyourownfont.com")!
    /// The site's "Your font" screen with the site chrome hidden, for the in-app FontSheet.
    static let embeddedFont = URL(string: "?embed=mac#done", relativeTo: website)!.absoluteURL
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
                Button("Your Font…") { project.showingFont = true }.keyboardShortcut(.return)
                Button("Open Website") { NSWorkspace.shared.open(Links.website) }
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo Stroke") { project.undo() }.keyboardShortcut("z").disabled(!project.canUndo)
                Button("Clear Glyph") { project.clear() }.keyboardShortcut(.delete).disabled(project.currentStrokes.isEmpty)
            }
            CommandMenu("Glyph") {
                Button("Previous Glyph") { project.previous() }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("Next Glyph") { project.next() }.keyboardShortcut(.rightArrow, modifiers: [])
                Divider()
                Button(project.isWriting ? "Exit Trackpad Mode" : "Enter Trackpad Mode") { project.isWriting.toggle() }
                    .keyboardShortcut("t")
                    .help("Fingers on the trackpad draw while this is on; Esc turns it off")
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
