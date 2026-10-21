import AppKit
import os

/// The drawing pad. Draws the glyph box with its guide lines and the strokes, and captures ink two ways:
///
/// 1. **Trackpad (NSTouch).** With `allowedTouchTypes = [.indirect]` AppKit delivers the raw finger positions of the
///    trackpad under the cursor as `touchesBegan/Moved/Ended/Cancelled`. `NSTouch.normalizedPosition` is the finger's
///    absolute position on the pad (origin bottom-left, 0…1 both axes) and `deviceSize` its physical size, so the whole
///    pad maps onto the glyph box: pad height → box height, x scaled by the same factor (`x = nx * aspect`, no
///    distortion), y flipped so it grows downward like the file format. One finger = pen; the first finger down is
///    tracked by identity until it lifts, other fingers are ignored. A tap with no movement is a one-point stroke (dot).
///
/// 2. **Mouse / pointer** inside the box as a fallback (click-drag). Mouse events that follow a trackpad touch within
///    a moment (the tap-to-click of the same finger) are swallowed so a touch dot does not become two dots.
///
/// **Writing mode.** Touches only arrive while the cursor is over this view and the window is key. Writing mode starts
/// with a click in the box (or ⌘T) and ends with Esc, a click anywhere outside the box, or the window losing focus.
/// While writing the cursor is hidden and parked over the box. The pointer is detached from the trackpad
/// (`CGAssociateMouseAndMouseCursorPosition(false)`) only while a finger is down, so between strokes the trackpad
/// still moves the pointer and the buttons stay reachable. Everything is restored when writing mode ends, the window
/// resigns key, the view leaves the window or the app quits. No Accessibility or other permission is needed.
final class PadView: NSView {
    private static let log = Logger(subsystem: "com.jzone3.HandwrittenFontBuilder", category: "trackpad")

    // Inputs (set by the SwiftUI representable)
    var strokes: [Stroke] = [] { didSet { needsDisplay = true } }
    var label: Character = "A" { didSet { needsDisplay = true } }
    var boxAspect: Double = GlyphSet.defaultBoxAspect { didSet { needsDisplay = true } }

    // Outputs
    var onStroke: ((Stroke) -> Void)?
    /// Called with the trackpad's width/height on every touch event (drives the "it works" light and the box aspect).
    var onTouch: ((Double) -> Void)?
    /// Return true when the key was handled.
    var onKey: ((NSEvent) -> Bool)?
    var onWritingModeChanged: ((Bool) -> Void)?

    private(set) var isWriting = false
    private var inProgress: Stroke = []
    private var strokeStart: TimeInterval = 0
    private var activeTouch: (any NSCopying & NSObjectProtocol)?
    private var mouseStroke = false
    private var lastTouchTime: TimeInterval = 0
    private var keyObserver: NSObjectProtocol?
    private var clickMonitor: Any?
    private var menuObserver: NSObjectProtocol?
    private var mouseDetached = false

    var isStrokeInProgress: Bool { !inProgress.isEmpty }

    override init(frame: NSRect) {
        super.init(frame: frame)
        allowedTouchTypes = [.indirect]
        wantsRestingTouches = false
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let menuObserver { NotificationCenter.default.removeObserver(menuObserver) }
        restoreCursor()
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    // MARK: Geometry

    /// The glyph box, fitted into the view with a margin, keeping `boxAspect`.
    var boxRect: CGRect {
        let inset = bounds.insetBy(dx: 20, dy: 20)
        guard inset.width > 0, inset.height > 0 else { return .zero }
        var h = inset.height
        var w = h * boxAspect
        if w > inset.width { w = inset.width; h = w / boxAspect }
        return CGRect(x: inset.midX - w / 2, y: inset.midY - h / 2, width: w, height: h)
    }

    private func viewPoint(_ p: StrokePoint, in box: CGRect) -> CGPoint {
        CGPoint(x: box.minX + p.x * box.height, y: box.minY + p.y * box.height)
    }

    private func glyphPoint(fromView v: CGPoint, in box: CGRect) -> (x: Double, y: Double) {
        ((v.x - box.minX) / box.height, (v.y - box.minY) / box.height)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let box = boxRect
        guard box.width > 0 else { return }

        NSColor.white.setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        NSColor(white: 0.75, alpha: 1).setStroke()
        let border = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)
        border.lineWidth = 1
        border.stroke()

        // Faint target character, top-left of the box.
        let labelFont = NSFont.systemFont(ofSize: box.height * 0.22, weight: .regular)
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: NSColor(white: 0.82, alpha: 1)]
        NSAttributedString(string: String(label), attributes: labelAttrs)
            .draw(at: CGPoint(x: box.minX + box.height * 0.04, y: box.minY + box.height * 0.01))

        // Guide lines: cap, x-height, baseline (bold), descender (bottom edge).
        let guides: [(Double, CGFloat, CGFloat)] = [
            (GlyphSet.capHeight, 1, 0.78), (GlyphSet.xHeight, 1, 0.78), (GlyphSet.baseline, 2, 0.35), (1.0, 1, 0.78),
        ]
        for (y, width, grey) in guides {
            let path = NSBezierPath()
            let vy = box.minY + CGFloat(y) * box.height
            path.move(to: CGPoint(x: box.minX, y: vy))
            path.line(to: CGPoint(x: box.maxX, y: vy))
            path.lineWidth = width
            NSColor(white: grey, alpha: 1).setStroke()
            path.stroke()
        }
        let tagFont = NSFont.systemFont(ofSize: 10)
        let tagAttrs: [NSAttributedString.Key: Any] = [.font: tagFont, .foregroundColor: NSColor(white: 0.6, alpha: 1)]
        for (y, name) in [(GlyphSet.capHeight, "cap"), (GlyphSet.xHeight, "x-height"), (GlyphSet.baseline, "baseline")] {
            NSAttributedString(string: name, attributes: tagAttrs)
                .draw(at: CGPoint(x: box.maxX - 52, y: box.minY + CGFloat(y) * box.height - 14))
        }

        NSColor.black.set()
        let lineWidth = box.height * 0.045
        for stroke in strokes { drawStroke(stroke, in: box, lineWidth: lineWidth) }
        if !inProgress.isEmpty { drawStroke(inProgress, in: box, lineWidth: lineWidth) }
    }

    private func drawStroke(_ stroke: Stroke, in box: CGRect, lineWidth: CGFloat) {
        let pts = StrokeGeometry.smoothed(stroke).map { viewPoint($0, in: box) }
        guard let first = pts.first else { return }
        if pts.count == 1 {
            NSBezierPath(ovalIn: CGRect(x: first.x - lineWidth / 2, y: first.y - lineWidth / 2, width: lineWidth, height: lineWidth)).fill()
            return
        }
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: first)
        for p in pts.dropFirst() { path.line(to: p) }
        path.stroke()
    }

    // MARK: Stroke lifecycle (shared by touch and mouse)

    private func beginStroke(x: Double, y: Double, at time: TimeInterval) {
        strokeStart = time
        inProgress = [StrokePoint(x: x, y: y, t: 0)]
        needsDisplay = true
    }

    private func continueStroke(x: Double, y: Double, at time: TimeInterval) {
        guard !inProgress.isEmpty else { return }
        let p = StrokePoint(x: x, y: y, t: (time - strokeStart) * 1000)
        if let last = inProgress.last, abs(last.x - p.x) < 1e-6, abs(last.y - p.y) < 1e-6 { return }
        inProgress.append(p)
        needsDisplay = true
    }

    private func endStroke() {
        guard !inProgress.isEmpty else { return }
        let stroke = inProgress
        inProgress = []
        needsDisplay = true
        onStroke?(stroke)
    }

    private func cancelStroke() {
        inProgress = []
        needsDisplay = true
    }

    // MARK: Trackpad touches

    enum TouchPhase { case began, moved, ended, cancelled }

    override func touchesBegan(with event: NSEvent) { route(event, .began, event.touches(matching: .began, in: self)) }
    override func touchesMoved(with event: NSEvent) { route(event, .moved, event.touches(matching: .moved, in: self)) }
    override func touchesEnded(with event: NSEvent) { route(event, .ended, event.touches(matching: .ended, in: self)) }
    override func touchesCancelled(with event: NSEvent) { route(event, .cancelled, event.touches(matching: .cancelled, in: self)) }

    private func route(_ event: NSEvent, _ phase: TouchPhase, _ touches: Set<NSTouch>) {
        for touch in touches {
            handleTouch(identity: touch.identity, normalized: touch.normalizedPosition, deviceSize: touch.deviceSize,
                        phase: phase, timestamp: event.timestamp)
        }
    }

    /// The one entry point for trackpad samples (real ones from the overrides above, synthetic ones from `simulateStroke`).
    func handleTouch(identity: any NSCopying & NSObjectProtocol, normalized: NSPoint, deviceSize: NSSize,
                     phase: TouchPhase, timestamp: TimeInterval) {
        lastTouchTime = ProcessInfo.processInfo.systemUptime
        let aspect = deviceSize.height > 0 ? Double(deviceSize.width / deviceSize.height) : GlyphSet.defaultBoxAspect
        onTouch?(aspect)
        let x = Double(normalized.x) * aspect
        let y = 1 - Double(normalized.y)
        Self.log.info("touch \(String(describing: phase), privacy: .public) nx=\(normalized.x, format: .fixed(precision: 3)) ny=\(normalized.y, format: .fixed(precision: 3)) -> glyph (\(x, format: .fixed(precision: 3)), \(y, format: .fixed(precision: 3))) device=\(deviceSize.width)x\(deviceSize.height)")

        switch phase {
        case .began:
            guard activeTouch == nil else { return }  // a second finger: ignore it
            activeTouch = identity
            if isWriting { detachMouse(); warpCursorIntoView() }
            beginStroke(x: x, y: y, at: timestamp)
        case .moved:
            guard let active = activeTouch, identity.isEqual(active) else { return }
            continueStroke(x: x, y: y, at: timestamp)
        case .ended:
            guard let active = activeTouch, identity.isEqual(active) else { return }
            activeTouch = nil
            continueStroke(x: x, y: y, at: timestamp)
            endStroke()
            reattachMouse()
        case .cancelled:
            guard let active = activeTouch, identity.isEqual(active) else { return }
            activeTouch = nil
            cancelStroke()
            reattachMouse()
        }
    }

    // MARK: Mouse fallback

    private var recentTouch: Bool { ProcessInfo.processInfo.systemUptime - lastTouchTime < 0.75 }

    private var pendingClick: CGPoint?

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        // In writing mode the trackpad is the pen: a tap-to-click must not draw or move anything.
        guard !isWriting, !recentTouch, activeTouch == nil else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard boxRect.contains(p) else { return }
        // A plain click starts writing mode; a click-drag is the mouse fallback and draws a stroke.
        pendingClick = p
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let start = pendingClick {
            guard hypot(p.x - start.x, p.y - start.y) > 4 else { return }
            pendingClick = nil
            mouseStroke = true
            let g = glyphPoint(fromView: start, in: boxRect)
            beginStroke(x: g.x, y: g.y, at: event.timestamp)
        }
        guard mouseStroke else { return }
        let g = glyphPoint(fromView: p, in: boxRect)
        continueStroke(x: g.x, y: g.y, at: event.timestamp)
    }

    override func mouseUp(with event: NSEvent) {
        if pendingClick != nil {
            pendingClick = nil
            enterWritingMode()
            return
        }
        guard mouseStroke else { return }
        mouseStroke = false
        endStroke()
    }

    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }

    // MARK: Writing mode

    func setWriting(_ on: Bool) {
        if on { enterWritingMode() } else { exitWritingMode() }
    }

    private func enterWritingMode() {
        guard !isWriting, window != nil else { return }
        isWriting = true
        window?.makeFirstResponder(self)
        NSCursor.hide()
        warpCursorIntoView()
        // Any click outside the box (a button, the glyph grid, the toolbar) ends writing mode and goes through as normal.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isWriting, event.window == self.window else { return event }
            let p = self.convert(event.locationInWindow, from: nil)
            if !self.boxRect.contains(p) { self.exitWritingMode() }
            return event
        }
        // Opening any menu shows the cursor again and the click monitor never sees menu-bar clicks, so treat it as a click outside the box.
        menuObserver = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            self?.exitWritingMode()
        }
        Self.log.info("writing mode on")
        onWritingModeChanged?(true)
    }

    func exitWritingMode() {
        guard isWriting else { return }
        isWriting = false
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        if let menuObserver { NotificationCenter.default.removeObserver(menuObserver) }
        menuObserver = nil
        restoreCursor()
        Self.log.info("writing mode off")
        onWritingModeChanged?(false)
    }

    /// Pointer stops following the finger for the duration of a stroke, so writing never drags the cursor onto a button.
    private func detachMouse() {
        guard !mouseDetached else { return }
        mouseDetached = true
        CGAssociateMouseAndMouseCursorPosition(0)
    }

    private func reattachMouse() {
        guard mouseDetached else { return }
        mouseDetached = false
        CGAssociateMouseAndMouseCursorPosition(1)
        if isWriting { warpCursorIntoView() }
    }

    /// Safe to call any number of times; undoes exactly what `enterWritingMode` / `detachMouse` did.
    private func restoreCursor() {
        mouseDetached = false
        CGAssociateMouseAndMouseCursorPosition(1)
        NSCursor.unhide()
    }

    /// Puts the system cursor at the centre of the box. CGWarpMouseCursorPosition takes global coordinates with the
    /// origin at the top-left of the main display; AppKit screen coordinates have it bottom-left.
    private func warpCursorIntoView() {
        guard let window, let mainScreen = NSScreen.screens.first else { return }
        let centre = CGPoint(x: boxRect.midX, y: boxRect.midY)
        let inWindow = convert(centre, to: nil)
        let onScreen = window.convertPoint(toScreen: inWindow)
        CGWarpMouseCursorPosition(CGPoint(x: onScreen.x, y: mainScreen.frame.height - onScreen.y))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = nil
        guard let window else { exitWritingMode(); return }
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window,
                                                             queue: .main) { [weak self] _ in self?.exitWritingMode() }
    }

    // MARK: Debug: a synthetic stroke through the real touch pipeline

    #if DEBUG
    /// Feeds a fake finger (a diagonal with a hook, on a 160×100 pt pad) through `handleTouch`, exactly the way the
    /// touch overrides do. Proves the mapping and the stroke pipeline on a Mac with no trackpad; it cannot prove that
    /// AppKit delivers touches to the view — only a real trackpad does that.
    func simulateStroke() {
        let identity = NSNumber(value: Int.random(in: 1...1_000_000))
        let device = NSSize(width: 160, height: 100)
        let t0 = ProcessInfo.processInfo.systemUptime
        let samples: [NSPoint] = (0...24).map { i in
            let s = Double(i) / 24
            return NSPoint(x: 0.2 + 0.6 * s, y: 0.75 - 0.5 * s + 0.15 * sin(s * .pi * 2))
        }
        handleTouch(identity: identity, normalized: samples[0], deviceSize: device, phase: .began, timestamp: t0)
        for (i, p) in samples.enumerated().dropFirst() {
            handleTouch(identity: identity, normalized: p, deviceSize: device, phase: .moved, timestamp: t0 + Double(i) * 0.012)
        }
        handleTouch(identity: identity, normalized: samples.last!, deviceSize: device, phase: .ended, timestamp: t0 + 0.3)
    }
    #endif
}
