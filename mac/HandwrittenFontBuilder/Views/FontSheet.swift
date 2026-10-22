import SwiftUI
import WebKit

/// "Your font": the website's finish screen (live preview, name, thickness, Download .otf, Publish, Share)
/// shown inside the app with the strokes handed over directly, so the Mac app does the whole job and the
/// result lands in the same database as fonts made on the site. The page is the one at Links.embeddedFont.
struct FontSheet: View {
    @EnvironmentObject private var project: Project
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Your font")
                    .font(.headline)
                Spacer()
                Button("Keep Writing") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            FontWebView(project: project, onKeepWriting: { dismiss() })
        }
        .frame(minWidth: 860, idealWidth: 1000, minHeight: 620, idealHeight: 760)
    }
}

struct FontWebView: NSViewRepresentable {
    let project: Project
    let onKeepWriting: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(project: project, onKeepWriting: onKeepWriting) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "native")
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.load(URLRequest(url: Links.embeddedFont))
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {
        let project: Project
        let onKeepWriting: () -> Void
        private var downloadURLs: [ObjectIdentifier: URL] = [:]

        init(project: Project, onKeepWriting: @escaping () -> Void) {
            self.project = project
            self.onKeepWriting = onKeepWriting
        }

        // MARK: Page loaded → hand over the strokes

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let json = String(decoding: StrokeFile.encode(project.contents), as: UTF8.self)
            webView.callAsyncJavaScript("window.HFB.importStrokes(data, projectId)",
                                        arguments: ["data": json, "projectId": project.projectID],
                                        in: nil, in: .page) { result in
                if case .failure(let error) = result { NSLog("FontSheet: importStrokes failed: \(error)") }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showLoadError(error, in: webView) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { showLoadError(error, in: webView) }

        private func showLoadError(_ error: Error, in webView: WKWebView) {
            let e = error as NSError
            if e.code == NSURLErrorCancelled { return }
            // "Frame load interrupted" (WebKitErrorDomain 102): the navigation became a download. The page is still there.
            if e.domain == "WebKitErrorDomain" && e.code == 102 { return }
            let html = """
            <body style="font-family:-apple-system;padding:40px;color:#111"><h2>Couldn’t reach buildyourownfont.com</h2>
            <p>\(error.localizedDescription)</p><p>Check your connection and try again, or use File → Export Strokes… and import the file on the website later.</p></body>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }

        // MARK: Messages from the page

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "keepWriting": onKeepWriting()
            case "fontName":
                if let value = body["value"] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { project.fontName = trimmed }
                }
            default: break
            }
        }

        // MARK: Navigation: downloads stay in the sheet, other pages open in the browser

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.shouldPerformDownload { decisionHandler(.download); return }
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url,
               !url.absoluteString.hasPrefix(Links.embeddedFont.absoluteString), !url.path.hasPrefix("/api/") {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
            return nil
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }

        // MARK: Downloads (.otf / .strokes.json) → Save panel

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = suggestedFilename
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
                guard response == .OK, let url = panel.url else { completionHandler(nil); return }
                try? FileManager.default.removeItem(at: url)
                self?.downloadURLs[ObjectIdentifier(download)] = url
                completionHandler(url)
            }
            if let window = download.webView?.window { panel.beginSheetModal(for: window, completionHandler: finish) } else { finish(panel.runModal()) }
        }

        func downloadDidFinish(_ download: WKDownload) {
            if let url = downloadURLs.removeValue(forKey: ObjectIdentifier(download)) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            downloadURLs.removeValue(forKey: ObjectIdentifier(download))
            if (error as NSError).code == NSURLErrorCancelled { return }
            let alert = NSAlert()
            alert.messageText = "Couldn’t save the file"
            alert.informativeText = error.localizedDescription
            if let window = download.webView?.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
        }

        // MARK: JavaScript dialogs (the page uses alert/confirm/prompt in a few places)

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = NSAlert()
            alert.messageText = message
            if let window = webView.window { alert.beginSheetModal(for: window) { _ in completionHandler() } } else { alert.runModal(); completionHandler() }
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            if let window = webView.window { alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn) } } else { completionHandler(alert.runModal() == .alertFirstButtonReturn) }
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let alert = NSAlert()
            alert.messageText = prompt
            let field = NSTextField(string: defaultText ?? "")
            field.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
            alert.accessoryView = field
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            if let window = webView.window {
                alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
            } else {
                completionHandler(alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
            }
        }
    }
}
