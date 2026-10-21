import Foundation

/// Reads and writes the `.strokes.json` interchange file described in FORMAT.md.
enum StrokeFile {
    static let format = "handwritten-font-strokes"
    static let version = 1
    static let source = "mac-app"
    static let fileExtension = "strokes.json"

    struct Contents {
        var fontName: String
        var glyphs: [Character: [Stroke]]
    }

    enum ReadError: LocalizedError {
        case notJSON, wrongFormat(String), unsupportedVersion(Int), noGlyphs

        var errorDescription: String? {
            switch self {
            case .notJSON: return "The file is not a JSON object."
            case .wrongFormat(let f): return "The file's format is “\(f)”, not “\(StrokeFile.format)”."
            case .unsupportedVersion(let v): return "The file is version \(v); this app reads version \(StrokeFile.version)."
            case .noGlyphs: return "The file has no “glyphs” object."
            }
        }
    }

    /// Glyphs in character-set order, one glyph per line; x/y to 4 decimals, t as whole milliseconds.
    static func encode(_ contents: Contents, createdAt: Date = Date()) -> Data {
        var out = "{\n"
        out += "  \"format\": \(json(format)),\n"
        out += "  \"version\": \(version),\n"
        out += "  \"source\": \(json(source)),\n"
        out += "  \"fontName\": \(json(contents.fontName)),\n"
        out += "  \"createdAt\": \(json(iso8601.string(from: createdAt))),\n"
        out += "  \"glyphs\": {\n"
        let drawn = GlyphSet.characters.filter { !(contents.glyphs[$0] ?? []).isEmpty }
        for (i, ch) in drawn.enumerated() {
            let strokes = contents.glyphs[ch]!.map { stroke in
                "[" + stroke.map { "[\(number($0.x)),\(number($0.y)),\(Int($0.t.rounded()))]" }.joined(separator: ",") + "]"
            }
            out += "    \(json(String(ch))): [" + strokes.joined(separator: ", ") + "]" + (i == drawn.count - 1 ? "\n" : ",\n")
        }
        out += "  }\n}\n"
        return Data(out.utf8)
    }

    static func decode(_ data: Data) throws -> Contents {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ReadError.notJSON }
        let fileFormat = root["format"] as? String ?? ""
        guard fileFormat == format else { throw ReadError.wrongFormat(fileFormat) }
        let fileVersion = root["version"] as? Int ?? 0
        guard fileVersion == version else { throw ReadError.unsupportedVersion(fileVersion) }
        guard let glyphsJSON = root["glyphs"] as? [String: Any] else { throw ReadError.noGlyphs }

        var glyphs: [Character: [Stroke]] = [:]
        for (key, value) in glyphsJSON {
            guard key.count == 1, let ch = key.first, GlyphSet.index(of: ch) != nil,
                  let strokesJSON = value as? [[Any]] else { continue }
            let strokes: [Stroke] = strokesJSON.compactMap { strokeJSON in
                let points: Stroke = strokeJSON.compactMap { pointJSON in
                    guard let p = pointJSON as? [Any], p.count >= 2,
                          let x = (p[0] as? NSNumber)?.doubleValue, let y = (p[1] as? NSNumber)?.doubleValue else { return nil }
                    let t = p.count >= 3 ? (p[2] as? NSNumber)?.doubleValue ?? 0 : 0
                    return StrokePoint(x: x, y: y, t: t)
                }
                return points.isEmpty ? nil : points
            }
            if !strokes.isEmpty { glyphs[ch] = strokes }  // empty array = "drawn as nothing" = missing, per FORMAT.md
        }
        return Contents(fontName: root["fontName"] as? String ?? "", glyphs: glyphs)
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func number(_ v: Double) -> String {
        var s = String(format: "%.4f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }

    private static func json(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case let c where c.value < 0x20: out += String(format: "\\u%04x", c.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}
