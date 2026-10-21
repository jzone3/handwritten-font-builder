import Foundation

/// The character set and the guide-line geometry shared with the website (see FORMAT.md at the repo root).
/// ) ] } > are mirrored from ( [ { < and curly quotes/dashes derived from ' " - by the website's font builder, so they are not drawn.
/// Units: 1.0 = the height of the glyph box, y grows downward.
enum GlyphSet {
    static let characters: [Character] = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ" + "abcdefghijklmnopqrstuvwxyz" + "0123456789" + ".,!?'\"-_([{/\\:;@#$%&*+=<~^|`"
    )

    static let capHeight = 0.20
    static let xHeight = 0.46
    static let baseline = 0.76

    /// Default box aspect (width / height) — the Mac trackpad's. Replaced by the real pad's aspect once a touch arrives.
    static let defaultBoxAspect = 1.6

    static func index(of character: Character) -> Int? { characters.firstIndex(of: character) }
}

/// One raw sample from the trackpad or the mouse: glyph-box coordinates plus milliseconds since the stroke started.
struct StrokePoint: Equatable {
    var x: Double
    var y: Double
    var t: Double
}

typealias Stroke = [StrokePoint]

enum StrokeGeometry {
    /// Light moving average of 3 for display only; the exported file keeps the raw points.
    static func smoothed(_ stroke: Stroke) -> Stroke {
        guard stroke.count > 2 else { return stroke }
        var out = stroke
        for i in 1..<(stroke.count - 1) {
            out[i].x = (stroke[i - 1].x + stroke[i].x + stroke[i + 1].x) / 3
            out[i].y = (stroke[i - 1].y + stroke[i].y + stroke[i + 1].y) / 3
        }
        return out
    }
}
