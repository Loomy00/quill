import AppKit
import SwiftUI

/// Visual state of the floating pill.
enum PillMode: Equatable {
    case collapsed, hover, holding, handsFree, processing, message(String, isError: Bool)

    @MainActor static func from(_ state: AppState, hovering: Bool) -> PillMode {
        switch state.phase {
        case .recording: return state.handsFree ? .handsFree : .holding
        case .transcribing, .cleaning: return .processing
        case .error(let m): return .message(m, isError: true)
        case .notice(let m): return .message(m, isError: false)
        case .idle: return hovering ? .hover : .collapsed
        }
    }

    /// Pill size for a horizontal layout; vertical layouts swap the axes.
    func size(vertical: Bool) -> CGSize {
        let s: CGSize
        switch self {
        case .collapsed: s = CGSize(width: 46, height: 10)
        case .hover: s = vertical ? CGSize(width: 96, height: 34) : CGSize(width: 214, height: 34)
        case .holding: s = CGSize(width: 116, height: 34)
        case .handsFree: s = CGSize(width: 176, height: 34)
        case .processing: s = CGSize(width: 76, height: 34)
        case .message: s = vertical ? CGSize(width: 34, height: 34) : CGSize(width: 320, height: 34)
        }
        return vertical ? CGSize(width: s.height, height: s.width) : s
    }
}

/// Hosts the pill in a fixed-size, borderless, non-activating panel pinned to a screen edge.
/// The panel never resizes (resizing under the cursor caused hover flicker); the pill animates
/// inside it, and clicks pass through the transparent area around the pill.
@MainActor
final class OverlayController {
    private unowned let state: AppState
    private var panel: OverlayPanel?
    private let model = OverlayModel()
    private var screenObserver: Any?
    private var mouseTimer: Timer?
    private var lastInsideAt = Date.distantPast
    private var dragGrab: CGPoint?

    /// The long side of the panel: wide enough for the largest pill.
    private let panelLength: CGFloat = 340
    private let panelThickness: CGFloat = 56
    /// Gap between the pill and the panel edge that faces the screen edge.
    static let pillInset: CGFloat = 6

    init(state: AppState) {
        self.state = state
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }

    // MARK: State

    func refresh() {
        let d = UserDefaults.standard
        model.triggerLabel = d.triggerKey.short
        if !model.dragging { model.position = d.overlayPosition }
        model.mode = PillMode.from(state, hovering: model.hovering)

        let idle = model.mode == .collapsed || model.mode == .hover
        guard d.bool(forKey: SettingsKey.overlayAlwaysVisible) || !idle || model.dragging else {
            panel?.orderOut(nil)
            stopMouseTracking()
            return
        }
        let panel = self.panel ?? makePanel()
        if !model.dragging {
            let frame = anchoredFrame()
            if panel.isVisible, panel.frame != frame {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.22
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().setFrame(frame, display: true)
                }
            } else if !panel.isVisible {
                panel.setFrame(frame, display: true)
            }
        }
        panel.orderFrontRegardless()
        startMouseTracking()
    }

    private func panelSize(for position: OverlayPosition) -> CGSize {
        position.isVertical ? CGSize(width: panelThickness, height: panelLength) : CGSize(width: panelLength, height: panelThickness)
    }

    private func currentScreen() -> NSScreen {
        if let panel, let s = panel.screen, !model.dragging { return s }
        return NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func anchoredFrame() -> NSRect {
        let f = currentScreen().visibleFrame
        let size = panelSize(for: model.position)
        let t = CGFloat(min(1, max(0, UserDefaults.standard.double(forKey: SettingsKey.overlayOffset))))
        func clampX(_ c: CGFloat) -> CGFloat { min(max(c - size.width / 2, f.minX), f.maxX - size.width) }
        func clampY(_ c: CGFloat) -> CGFloat { min(max(c - size.height / 2, f.minY), f.maxY - size.height) }
        switch model.position {
        case .bottom: return NSRect(x: clampX(f.minX + t * f.width), y: f.minY, width: size.width, height: size.height)
        case .top: return NSRect(x: clampX(f.minX + t * f.width), y: f.maxY - size.height, width: size.width, height: size.height)
        case .left: return NSRect(x: f.minX, y: clampY(f.minY + t * f.height), width: size.width, height: size.height)
        case .right: return NSRect(x: f.maxX - size.width, y: clampY(f.minY + t * f.height), width: size.width, height: size.height)
        }
    }

    /// Where the pill is drawn, in screen coordinates.
    private func pillRect(in frame: NSRect, mode: PillMode) -> NSRect {
        let s = mode.size(vertical: model.position.isVertical)
        let i = Self.pillInset
        switch model.position {
        case .bottom: return NSRect(x: frame.midX - s.width / 2, y: frame.minY + i, width: s.width, height: s.height)
        case .top: return NSRect(x: frame.midX - s.width / 2, y: frame.maxY - i - s.height, width: s.width, height: s.height)
        case .left: return NSRect(x: frame.minX + i, y: frame.midY - s.height / 2, width: s.width, height: s.height)
        case .right: return NSRect(x: frame.maxX - i - s.width, y: frame.midY - s.height / 2, width: s.width, height: s.height)
        }
    }

    // MARK: Hover (polled, so window changes can't cause enter/exit loops)

    private func startMouseTracking() {
        guard mouseTimer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.trackMouse() }
        }
        RunLoop.main.add(t, forMode: .common)
        mouseTimer = t
    }

    private func stopMouseTracking() {
        mouseTimer?.invalidate()
        mouseTimer = nil
    }

    private func trackMouse() {
        guard let panel, panel.isVisible else { return }
        if model.dragging { panel.ignoresMouseEvents = false; return }
        let mouse = NSEvent.mouseLocation
        let pill = pillRect(in: panel.frame, mode: model.mode)
        // Generous hit area around the slim idle pill; tighter once expanded.
        let inside = pill.insetBy(dx: -10, dy: -10).contains(mouse)
        panel.ignoresMouseEvents = !pill.insetBy(dx: -4, dy: -4).contains(mouse)

        if inside { lastInsideAt = Date() }
        let shouldHover = inside || Date().timeIntervalSince(lastInsideAt) < 0.25
        if shouldHover != model.hovering {
            model.hovering = shouldHover
            if state.phase == .idle { model.mode = PillMode.from(state, hovering: shouldHover) }
        }
    }

    // MARK: Dragging — drop anywhere, snaps to the nearest screen edge

    func dragChanged() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if dragGrab == nil {
            dragGrab = CGPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
            model.dragging = true
        }
        guard let grab = dragGrab else { return }
        panel.setFrameOrigin(NSPoint(x: mouse.x - grab.x, y: mouse.y - grab.y))
    }

    func dragEnded() {
        guard dragGrab != nil else { return }
        dragGrab = nil
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        let distances: [(OverlayPosition, CGFloat)] = [
            (.bottom, mouse.y - f.minY), (.top, f.maxY - mouse.y), (.left, mouse.x - f.minX), (.right, f.maxX - mouse.x),
        ]
        let edge = distances.min(by: { $0.1 < $1.1 })!.0
        let offset = edge.isVertical ? (mouse.y - f.minY) / f.height : (mouse.x - f.minX) / f.width
        // Snap near the middle so "centered" is easy to hit.
        let snapped = abs(offset - 0.5) < 0.06 ? 0.5 : Double(min(1, max(0, offset)))

        model.dragging = false
        model.position = edge
        let d = UserDefaults.standard
        d.set(edge.rawValue, forKey: SettingsKey.overlayPosition)
        d.set(snapped, forKey: SettingsKey.overlayOffset)
        // Move to the drop screen, then animate into place.
        if let panel { panel.setFrame(NSRect(origin: panel.frame.origin, size: panelSize(for: edge)), display: false) }
        refresh()
    }

    // MARK: Panel

    private func makePanel() -> OverlayPanel {
        let p = OverlayPanel(contentRect: NSRect(origin: .zero, size: panelSize(for: model.position)),
                             styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.ignoresMouseEvents = true

        let root = OverlayView(model: model,
                               onStart: { [weak self] in self?.state.startRecording(handsFree: true) },
                               onStop: { [weak self] in self?.state.stopAndProcess() },
                               onCancel: { [weak self] in self?.state.cancel() },
                               onDragChanged: { [weak self] in self?.dragChanged() },
                               onDragEnded: { [weak self] in self?.dragEnded() })
            .environmentObject(state)
        p.contentView = FirstMouseHostingView(rootView: root)
        panel = p
        return p
    }
}

final class OverlayModel: ObservableObject {
    @Published var mode: PillMode = .collapsed
    @Published var position: OverlayPosition = .bottom
    @Published var hovering = false
    @Published var dragging = false
    @Published var triggerLabel = "fn"
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Pill view

struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    @EnvironmentObject var state: AppState
    var onStart: () -> Void
    var onStop: () -> Void
    var onCancel: () -> Void
    var onDragChanged: () -> Void
    var onDragEnded: () -> Void

    private var vertical: Bool { model.position.isVertical }

    private var alignment: Alignment {
        switch model.position {
        case .bottom: return .bottom
        case .top: return .top
        case .left: return .leading
        case .right: return .trailing
        }
    }

    var body: some View {
        let size = model.mode.size(vertical: vertical)
        pill
            .frame(width: size.width, height: size.height)
            .scaleEffect(model.dragging ? 1.08 : 1)
            .padding(OverlayController.pillInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .animation(.spring(response: 0.3, dampingFraction: 0.86), value: model.mode)
            .animation(.spring(response: 0.3, dampingFraction: 0.86), value: model.dragging)
    }

    private var pill: some View {
        let shape = Capsule(style: .continuous)
        let collapsed = model.mode == .collapsed && !model.dragging
        return ZStack {
            shape.fill(Theme.bg.opacity(collapsed ? 0.6 : 0.94))
            shape.strokeBorder(collapsed ? Theme.text.opacity(0.35) : Theme.accent.opacity(0.28), lineWidth: 1)
            content.transition(.opacity)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(collapsed ? 0 : 0.4), radius: 10, y: 3)
        .contentShape(shape)
        .onTapGesture { if model.mode == .hover || model.mode == .collapsed { onStart() } }
        .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { _ in onDragChanged() }
            .onEnded { _ in onDragEnded() })
        .help(helpText)
    }

    @ViewBuilder private var content: some View {
        switch model.mode {
        case .collapsed:
            EmptyView()
        case .hover:
            stack {
                QuillLogo(tile: false).frame(width: 18, height: 18)
                if vertical {
                    Text(model.triggerLabel).font(Theme.mono(10, weight: .semibold)).foregroundStyle(Theme.muted)
                } else {
                    (Text("hold ").foregroundColor(Theme.muted) + Text(model.triggerLabel).foregroundColor(Theme.accent)
                     + Text(" or click to write").foregroundColor(Theme.muted))
                        .font(Theme.mono(11, weight: .medium))
                        .fixedSize()
                }
            }
        case .holding:
            Waveform(levels: state.levels, vertical: vertical).padding(vertical ? .vertical : .horizontal, 14)
        case .handsFree:
            stack {
                CircleButton(symbol: "xmark", tint: Theme.surfaceHi, action: onCancel).help("Cancel (Esc)")
                Waveform(levels: state.levels, vertical: vertical)
                CircleButton(symbol: "stop.fill", tint: Theme.rec, action: onStop).help("Finish (tap \(model.triggerLabel))")
            }
            .padding(vertical ? .vertical : .horizontal, 6)
        case .processing:
            ProcessingDots(vertical: vertical)
        case .message(let text, let isError):
            stack {
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "doc.on.clipboard.fill")
                    .foregroundStyle(isError ? Theme.rec : Theme.accent)
                if !vertical {
                    Text(text).font(Theme.mono(10.5, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    @ViewBuilder private func stack<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        if vertical { VStack(spacing: 8, content: c) } else { HStack(spacing: 8, content: c) }
    }

    private var helpText: String {
        if case .message(let m, _) = model.mode { return m }
        return "Hold \(model.triggerLabel) or click to dictate · double-tap \(model.triggerLabel) for hands-free · drag to move"
    }
}

private struct CircleButton: View {
    let symbol: String
    let tint: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(tint))
        }
        .buttonStyle(.plain)
    }
}

struct Waveform: View {
    var levels: [Float]
    var vertical = false
    private let bars = 14

    var body: some View {
        let recent = Array(levels.suffix(bars))
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 2.5)) : AnyLayout(HStackLayout(spacing: 2.5))
        layout {
            ForEach(recent.indices, id: \.self) { i in
                let v = CGFloat(max(0.12, min(1, recent[i] * 1.6)))
                Capsule()
                    .fill(Theme.accent.opacity(0.55 + 0.45 * Double(v)))
                    .frame(width: vertical ? 18 * v : 2.5, height: vertical ? 2.5 : 18 * v)
            }
        }
        .shadow(color: Theme.accent.opacity(0.6), radius: 3)
        .animation(.easeOut(duration: 0.08), value: levels)
    }
}

private struct ProcessingDots: View {
    var vertical: Bool
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let layout = vertical ? AnyLayout(VStackLayout(spacing: 5)) : AnyLayout(HStackLayout(spacing: 5))
            layout {
                ForEach(0..<3) { i in
                    let phase = sin(t * 5 - Double(i) * 0.7)
                    Circle().fill(Theme.accent)
                        .frame(width: 5, height: 5)
                        .opacity(0.35 + 0.65 * max(0, phase))
                        .scaleEffect(0.85 + 0.25 * max(0, phase))
                }
            }
        }
    }
}
