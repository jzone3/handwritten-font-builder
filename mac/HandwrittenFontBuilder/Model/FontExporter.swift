import Foundation
import WebKit

/// Builds the `.otf` on this Mac, with no network: the website's own font engine (tracer.js, fontbuild.js,
/// opentype.min.js, bundled from `site/`) runs in a hidden web view, because the tracer rasterizes on a canvas.
@MainActor
final class FontExporter: NSObject, WKNavigationDelegate {
    enum ExportError: LocalizedError {
        case engineMissing(String), engineFailed(String), badOutput

        var errorDescription: String? {
            switch self {
            case .engineMissing(let file): return "The font engine file “\(file)” is missing from the app."
            case .engineFailed(let message): return message
            case .badOutput: return "The font engine did not return a font."
            }
        }
    }

    /// Order matters: each script uses the globals of the ones before it.
    private static let engineFiles = ["opentype.min", "tracer", "fontbuild", "export-font"]

    private let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
    private var pageLoaded: ((Result<Void, Error>) -> Void)?
    /// Keeps each exporter alive until its completion handler has run.
    private static var running: [ObjectIdentifier: FontExporter] = [:]

    static func buildFont(from contents: StrokeFile.Contents, completion: @escaping (Result<Data, Error>) -> Void) {
        let exporter = FontExporter()
        running[ObjectIdentifier(exporter)] = exporter
        exporter.build(contents) { result in
            running[ObjectIdentifier(exporter)] = nil
            completion(result)
        }
    }

    private func build(_ contents: StrokeFile.Contents, completion: @escaping (Result<Data, Error>) -> Void) {
        let scripts: [String]
        do {
            scripts = try FontExporter.engineFiles.map { name in
                guard let url = Bundle.main.url(forResource: name, withExtension: "js") else { throw ExportError.engineMissing("\(name).js") }
                return try String(contentsOf: url, encoding: .utf8)
            }
        } catch {
            completion(.failure(error))
            return
        }
        pageLoaded = { [weak self] loaded in
            guard let self else { return }
            if case .failure(let error) = loaded { completion(.failure(error)); return }
            self.run(scripts: scripts[...], contents: contents, completion: completion)
        }
        webView.navigationDelegate = self
        webView.loadHTMLString("<!doctype html><html><body></body></html>", baseURL: nil)
    }

    private func run(scripts: ArraySlice<String>, contents: StrokeFile.Contents, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let script = scripts.first else {
            let json = String(decoding: StrokeFile.encode(contents), as: UTF8.self)
            webView.callAsyncJavaScript("return window.HFBExport.build(data, name)",
                                        arguments: ["data": json, "name": contents.fontName],
                                        in: nil, in: .page) { result in
                switch result {
                case .failure(let error): completion(.failure(FontExporter.readable(error)))
                case .success(let value):
                    guard let object = value as? [String: Any], let base64 = object["otf"] as? String,
                          let data = Data(base64Encoded: base64), data.starts(with: Array("OTTO".utf8)) else {
                        completion(.failure(ExportError.badOutput))
                        return
                    }
                    completion(.success(data))
                }
            }
            return
        }
        // "; null" so the script's completion value is something WebKit can hand back.
        webView.evaluateJavaScript(script + "\n; null") { [weak self] _, error in
            if let error { completion(.failure(FontExporter.readable(error))); return }
            self?.run(scripts: scripts.dropFirst(), contents: contents, completion: completion)
        }
    }

    /// WebKit reports a thrown JavaScript error as a generic message; the real one is in userInfo.
    private static func readable(_ error: Error) -> Error {
        if let message = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String {
            return ExportError.engineFailed(message.replacingOccurrences(of: "Error: ", with: ""))
        }
        return error
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishLoad(.success(())) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finishLoad(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finishLoad(.failure(error)) }

    private func finishLoad(_ result: Result<Void, Error>) {
        let handler = pageLoaded
        pageLoaded = nil
        handler?(result)
    }
}
