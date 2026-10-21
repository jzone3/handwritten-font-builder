import AppKit
import SwiftUI

/// One-time "thanks for downloading" sheet on first launch; Get Started opens the author's X profile behind the app.
enum Welcome {
    static let shownKey = "welcomeShown"

    @MainActor
    static func showIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: shownKey) else { return }
        defaults.set(true, forKey: shownKey)

        let sheet = NSWindow(contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        sheet.titlebarAppearsTransparent = true
        sheet.titleVisibility = .hidden
        sheet.isReleasedWhenClosed = false
        let host = NSHostingController(rootView: WelcomeView { [weak sheet] in
            guard let sheet else { return }
            if let parent = sheet.sheetParent { parent.endSheet(sheet) } else { sheet.orderOut(nil) }
            openInBackground(Links.author)
        })
        host.sizingOptions = [.preferredContentSize]
        sheet.contentViewController = host
        sheet.setContentSize(host.view.fittingSize)

        if let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }),
           window.attachedSheet == nil {
            window.beginSheet(sheet)
        } else {
            sheet.center()
            sheet.makeKeyAndOrderFront(nil)
        }
    }

    /// Opens the URL behind the app. A browser that has to launch first comes to the front anyway
    /// (`activates = false` only covers a running one), so the app takes the front back when that happens.
    static func openInBackground(_ url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        let center = NSWorkspace.shared.notificationCenter
        var token: NSObjectProtocol?
        token = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app != .current else { return }
            NSApp.activate(ignoringOtherApps: true)
            (NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeKey })?.makeKeyAndOrderFront(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { token.map(center.removeObserver) }
        NSWorkspace.shared.open(url, configuration: config)
    }
}

private struct WelcomeView: View {
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
                .padding(.bottom, 18)
            Text("Thanks for downloading\nHandwritten Font Builder")
                .font(.system(size: 20, weight: .semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)
            Text("Write each letter on your trackpad with a finger, export the strokes, and the website turns them into a real font you can install.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
            Text("I built this with Devin. Open source.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 28)
            HStack(spacing: 12) {
                Button("Source Code") { Welcome.openInBackground(Links.repo) }
                    .buttonStyle(.bordered)
                Button("Get Started", action: done)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 36)
        .padding(.top, 36)
        .padding(.bottom, 28)
        .frame(width: 400)
        .background(Button("Close", action: done).keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true))
    }
}
