import AppKit
import SwiftUI

/// Custom About window: icon, version, links to @imjaredz, the source and Devin.
enum About {
    private static var window: NSWindow?

    @MainActor
    static func show() {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let host = NSHostingController(rootView: AboutView())
        host.sizingOptions = [.preferredContentSize]
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "About Handwritten Font Builder"
        w.isReleasedWhenClosed = false
        w.setContentSize(host.view.fittingSize)
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Handwritten Font Builder").font(.title2.weight(.semibold))
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                .foregroundStyle(.secondary)
            Text("Write letters on your trackpad, turn them into a font.").foregroundStyle(.secondary)
            HStack {
                Button("Open Website") { NSWorkspace.shared.open(Links.website) }.buttonStyle(.borderedProminent)
                Button("Source Code") { NSWorkspace.shared.open(Links.repo) }.buttonStyle(.bordered)
                Button("@imjaredz") { NSWorkspace.shared.open(Links.author) }.buttonStyle(.bordered)
            }
            .padding(.top, 8)
            Button("Built with Devin") { NSWorkspace.shared.open(Links.devin) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .padding(.horizontal, 36)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .frame(width: 420)
    }
}
