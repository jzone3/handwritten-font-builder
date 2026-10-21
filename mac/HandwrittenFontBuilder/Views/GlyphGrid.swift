import SwiftUI

/// Progress strip: every character in the set, drawn ones as a small thumbnail of their strokes, undrawn ones grey.
struct GlyphGrid: View {
    @EnvironmentObject private var project: Project

    private let columns = Array(repeating: GridItem(.fixed(40), spacing: 4), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(project.drawnCount) of \(GlyphSet.characters.count) drawn")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(Array(GlyphSet.characters.enumerated()), id: \.offset) { index, ch in
                            GlyphCell(character: ch, strokes: project.strokes(for: ch), aspect: project.boxAspect,
                                      selected: index == project.currentIndex)
                                .id(index)
                                .onTapGesture {
                                    project.currentIndex = index
                                    project.focusPad()
                                }
                        }
                    }
                    .padding(10)
                }
                .onChange(of: project.currentIndex) { index in
                    withAnimation { proxy.scrollTo(index, anchor: .center) }
                }
            }
        }
    }
}

struct GlyphCell: View {
    let character: Character
    let strokes: [Stroke]
    let aspect: Double
    let selected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(strokes.isEmpty ? Color.secondary.opacity(0.08) : Color(nsColor: .textBackgroundColor))
            if strokes.isEmpty {
                Text(String(character))
                    .font(.system(size: 16, weight: .regular, design: .default))
                    .foregroundStyle(Color.secondary.opacity(0.7))
            } else {
                GlyphThumbnail(strokes: strokes, aspect: aspect)
                    .padding(3)
            }
        }
        .frame(width: 40, height: 40)
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(selected ? Color.primary : Color.secondary.opacity(0.15),
                                                                lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
        .help(String(character))
    }
}

/// Strokes of one glyph scaled to fit; the glyph box is `aspect` wide for 1 high.
struct GlyphThumbnail: View {
    let strokes: [Stroke]
    let aspect: Double

    var body: some View {
        Canvas { context, size in
            let aspect = CGFloat(aspect)
            let scale: CGFloat = min(size.height, size.width / aspect)
            let boxWidth: CGFloat = scale * aspect
            let box = CGRect(x: (size.width - boxWidth) / 2, y: (size.height - scale) / 2, width: boxWidth, height: scale)
            let lineWidth: CGFloat = max(1, scale * 0.045)
            for stroke in strokes {
                let pts: [CGPoint] = StrokeGeometry.smoothed(stroke).map { p in
                    CGPoint(x: box.minX + CGFloat(p.x) * scale, y: box.minY + CGFloat(p.y) * scale)
                }
                guard let first = pts.first else { continue }
                if pts.count == 1 {
                    context.fill(Path(ellipseIn: CGRect(x: first.x - lineWidth / 2, y: first.y - lineWidth / 2,
                                                        width: lineWidth, height: lineWidth)), with: .color(.primary))
                    continue
                }
                var path = Path()
                path.move(to: first)
                for p in pts.dropFirst() { path.addLine(to: p) }
                context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
