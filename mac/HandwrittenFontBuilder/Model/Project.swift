import AppKit
import Combine

/// The one open project: font name, strokes per glyph, the selected glyph, per-glyph undo, and autosave.
@MainActor
final class Project: ObservableObject {
    static let shared = Project()

    @Published var fontName: String { didSet { if fontName != oldValue { scheduleAutosave() } } }
    @Published private(set) var glyphs: [Character: [Stroke]] = [:]
    @Published var currentIndex: Int { didSet { UserDefaults.standard.set(currentIndex, forKey: Keys.currentIndex) } }
    /// Trackpad mode: cursor hidden and parked over the pad so every trackpad touch reaches it; off = mouse mode (see PadView).
    @Published var isWriting = false
    /// True for a moment after each trackpad touch — the "it works" light in the control bar.
    @Published private(set) var trackpadActive = false
    @Published private(set) var touchCount = 0
    /// Width / height of the drawing box; follows the real trackpad once a touch reports its deviceSize.
    @Published var boxAspect = GlyphSet.defaultBoxAspect

    weak var pad: PadView?

    private var undoStacks: [Character: [[Stroke]]] = [:]
    private var autosaveWork: DispatchWorkItem?
    private var activityReset: DispatchWorkItem?

    private enum Keys {
        static let currentIndex = "currentIndex"
    }

    static let defaultFontName = "My Handwriting"

    private init() {
        fontName = Project.defaultFontName
        let saved = UserDefaults.standard.integer(forKey: Keys.currentIndex)
        currentIndex = GlyphSet.characters.indices.contains(saved) ? saved : 0
        loadAutosave()
    }

    // MARK: Glyphs

    var current: Character { GlyphSet.characters[currentIndex] }
    var currentStrokes: [Stroke] { glyphs[current] ?? [] }
    var drawnCount: Int { glyphs.values.filter { !$0.isEmpty }.count }
    var canUndo: Bool { !(undoStacks[current] ?? []).isEmpty }
    func strokes(for character: Character) -> [Stroke] { glyphs[character] ?? [] }

    func add(_ stroke: Stroke) {
        guard !stroke.isEmpty else { return }
        pushUndo()
        glyphs[current, default: []].append(stroke)
        scheduleAutosave()
    }

    func undo() {
        guard var stack = undoStacks[current], let previous = stack.popLast() else { return }
        undoStacks[current] = stack
        glyphs[current] = previous
        if previous.isEmpty { glyphs[current] = nil }
        scheduleAutosave()
    }

    func clear() {
        guard !currentStrokes.isEmpty else { return }
        pushUndo()
        glyphs[current] = nil
        scheduleAutosave()
    }

    func next() { currentIndex = min(currentIndex + 1, GlyphSet.characters.count - 1) }
    func previous() { currentIndex = max(currentIndex - 1, 0) }

    func jump(to character: Character) {
        if let i = GlyphSet.index(of: character) { currentIndex = i }
    }

    private func pushUndo() {
        var stack = undoStacks[current] ?? []
        stack.append(currentStrokes)
        if stack.count > 100 { stack.removeFirst() }
        undoStacks[current] = stack
    }

    // MARK: Trackpad activity

    func noteTouch(deviceAspect: Double) {
        touchCount += 1
        trackpadActive = true
        if deviceAspect > 0.5, deviceAspect < 4, abs(deviceAspect - boxAspect) > 0.005 { boxAspect = deviceAspect }
        activityReset?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.trackpadActive = false }
        activityReset = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    func focusPad() {
        if let pad { pad.window?.makeFirstResponder(pad) }
    }

    // MARK: Whole-project operations

    func replace(with contents: StrokeFile.Contents) {
        glyphs = contents.glyphs
        undoStacks = [:]
        if !contents.fontName.isEmpty { fontName = contents.fontName }
        scheduleAutosave()
    }

    func reset() {
        glyphs = [:]
        undoStacks = [:]
        fontName = Project.defaultFontName
        currentIndex = 0
        scheduleAutosave()
    }

    var contents: StrokeFile.Contents { StrokeFile.Contents(fontName: fontName, glyphs: glyphs) }

    // MARK: Autosave (Application Support/Handwritten Font Builder/project.strokes.json)

    static let autosaveURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Handwritten Font Builder", isDirectory: true)
            .appendingPathComponent("project.strokes.json")
    }()

    private func scheduleAutosave() {
        autosaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        autosaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        autosaveWork?.cancel()
        let url = Project.autosaveURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try StrokeFile.encode(contents).write(to: url, options: .atomic)
        } catch {
            NSLog("autosave failed: \(error)")
        }
    }

    private func loadAutosave() {
        guard let data = try? Data(contentsOf: Project.autosaveURL),
              let saved = try? StrokeFile.decode(data) else { return }
        glyphs = saved.glyphs
        if !saved.fontName.isEmpty { fontName = saved.fontName }
    }
}
