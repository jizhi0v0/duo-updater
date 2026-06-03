#if os(macOS)
import AppKit
import QuartzCore
import SwiftUI

@available(macOS 13.0, *)
@MainActor
final class FloatingDropPanel: NSPanel {
    private weak var panelController: PermissionFlowController?
    private let hostingView: NSHostingView<AnyView>
    private let sizingView: NSHostingView<AnyView>
    private let initialPanelWidth: CGFloat = 420

    /// System Settings has a leading sidebar. Matching the trailing content
    /// area width keeps the floating panel visually aligned with the pane that
    /// the user is actively interacting with.
    private let sidebarWidth: CGFloat = 230
    private let screenInset: CGFloat = 12
    private let minimumPanelHeight: CGFloat = 96
    private let sizingHeightLimit: CGFloat = 4096

    /// Launch animation constants tuned to feel responsive without making the
    /// panel overshoot or jitter while the target window is still settling.
    private let animationDuration: TimeInterval = 0.72
    private let animationResponse: Double = 0.72
    private let initialAlpha: CGFloat = 0.9
    private let minimumLaunchScale: CGFloat = 0.58
    private var launchTimer: Timer?
    private var displayLink: AnyObject?
    private var launchStartTime: CFTimeInterval = 0
    private var launchSourceCenter = CGPoint.zero
    private var launchTargetFrame = NSRect.zero
    private var isAnimatingLaunch = false
    private var localeIdentifier: String?

    init(controller: PermissionFlowController) {
        panelController = controller
        localeIdentifier = controller.localeIdentifier
        let panelView = Self.makePanelView(controller: controller, localeIdentifier: controller.localeIdentifier)
        hostingView = NSHostingView(rootView: panelView)
        sizingView = NSHostingView(rootView: panelView)
        super.init(
            contentRect: CGRect(origin: .zero, size: CGSize(width: initialPanelWidth, height: minimumPanelHeight)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        // Prevent the hosting view from pushing its SwiftUI layout size back
        // onto the enclosing NSWindow. `NSHostingView.sizingOptions` defaults
        // to `[.intrinsicContentSize]` on macOS 13.3+, which makes the host
        // re-advertise the SwiftUI root view's intrinsic size to the window
        // on every layout pass. For the panel content (ultraThinMaterial
        // background + `.fixedSize(vertical: true)` + a markdown-wrapped
        // header `AttributedString`), that intrinsic value diverges from the
        // `sizingView.fittingSize` that `measuredPanelHeight` uses — so the
        // window auto-grows well past the content-size we set, and every
        // subsequent `setFrame(...)` from `snap(to:)` is reverted on the
        // next layout tick, leaving the panel stuck off-screen.
        //
        // Opting out of `.intrinsicContentSize` makes the existing
        // `measuredPanelHeight` → `setContentSize` / `snap(to:)` pipeline the
        // single source of truth for panel geometry.
        if #available(macOS 13.3, *) {
            hostingView.sizingOptions = []
        }
        // Layer-backed so the launch animation can scale the content via a layer
        // transform instead of resizing the window (which would relayout SwiftUI).
        hostingView.wantsLayer = true
        contentView = hostingView
        setContentSize(CGSize(width: initialPanelWidth, height: measuredPanelHeight(for: initialPanelWidth)))
    }

    /// Updates the locale environment used by the floating panel content.
    func updateLocaleIdentifier(_ localeIdentifier: String?) {
        guard self.localeIdentifier != localeIdentifier else { return }
        self.localeIdentifier = localeIdentifier
        guard let panelController else { return }
        let panelView = Self.makePanelView(controller: panelController, localeIdentifier: localeIdentifier)
        hostingView.rootView = panelView
        sizingView.rootView = panelView
        setContentSize(CGSize(width: frame.width, height: measuredPanelHeight(for: frame.width)))
    }

    /// The panel intentionally stays non-activating so System Settings remains
    /// the visible focus owner underneath it.
    override var canBecomeKey: Bool { false }

    override var canBecomeMain: Bool { false }

    /// If the system temporarily tries to key this panel, immediately ask the
    /// controller to keep System Settings visually frontmost underneath it.
    override func becomeKey() {
        super.becomeKey()
        panelController?.keepSettingsVisible()
    }

    /// Mirrors becomeKey() for main-window promotion attempts so the helper
    /// remains non-disruptive to the actual System Settings interaction.
    override func becomeMain() {
        super.becomeMain()
        panelController?.keepSettingsVisible()
    }

    /// Keeps System Settings visually present when the panel receives a mouse
    /// down event, while still forwarding the event through normal handling.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            panelController?.keepSettingsVisible()
        }
        super.sendEvent(event)
    }

    /// `displayLink(target:)` retains its target, so stop the ticker on close to
    /// avoid a retain cycle keeping a dismissed panel (and its flight) alive.
    override func close() {
        stopLaunchAnimation()
        super.close()
    }

    /// Shows the panel at its current frame without any positioning changes.
    /// Clears any residual flight state so a centered fallback renders at full
    /// size with its shadow intact.
    func show() {
        stopLaunchAnimation()
        isAnimatingLaunch = false
        alphaValue = 1
        hasShadow = true
        applyContentScale(1)
        orderFrontRegardless()
    }

    /// Animates the panel from the triggering UI element toward the current
    /// System Settings window frame once the destination becomes available.
    ///
    /// The window holds its **final size** for the whole flight: only its origin
    /// moves along the curve and the content layer scales up from
    /// `minimumLaunchScale`. Resizing the window each frame would force the
    /// SwiftUI host (wrapped markdown text + an app icon) to re-layout 60×/sec,
    /// which is what made the motion drop frames. A `CADisplayLink` paces the
    /// steps to the display refresh instead of a free-running `Timer`.
    func present(from sourceFrameInScreen: CGRect, to settingsFrame: CGRect) {
        stopLaunchAnimation()
        let targetFrame = targetFrame(for: settingsFrame)

        guard sourceFrameInScreen.isEmpty == false else {
            finishLaunch(at: targetFrame)
            return
        }

        isAnimatingLaunch = true
        launchTargetFrame = targetFrame
        launchSourceCenter = CGPoint(x: sourceFrameInScreen.midX, y: sourceFrameInScreen.midY)
        launchStartTime = CACurrentMediaTime()

        // The transparent margins around the scaled-down card would otherwise
        // cast a full-size shadow box at the source, so suppress it in flight.
        hasShadow = false
        alphaValue = initialAlpha
        setFrame(frame(ofSize: targetFrame.size, centeredOn: launchSourceCenter), display: false)
        applyContentScale(minimumLaunchScale)
        orderFrontRegardless()

        startLaunchTicker()
        stepLaunchAnimation()
    }

    /// Scales the hosted content about its center without disturbing the window
    /// size. Wrapped in a non-animating transaction so the implicit Core
    /// Animation action doesn't fight the per-step updates.
    private func applyContentScale(_ scale: CGFloat) {
        guard let layer = contentView?.layer else { return }
        let bounds = layer.bounds
        let transform = CGAffineTransform(translationX: bounds.midX, y: bounds.midY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -bounds.midX, y: -bounds.midY)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setAffineTransform(transform)
        CATransaction.commit()
    }

    /// Returns a window frame of `size` whose center sits at `center`.
    private func frame(ofSize size: CGSize, centeredOn center: CGPoint) -> CGRect {
        CGRect(
            x: center.x - (size.width * 0.5),
            y: center.y - (size.height * 0.5),
            width: size.width,
            height: size.height
        )
    }

    /// Starts the display-synced ticker, falling back to a timer pre-macOS 14.
    private func startLaunchTicker() {
        if #available(macOS 14.0, *), let view = contentView {
            let link = view.displayLink(target: self, selector: #selector(handleDisplayLink(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stepLaunchAnimation()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            launchTimer = timer
        }
    }

    @available(macOS 14.0, *)
    @objc private func handleDisplayLink(_ sender: CADisplayLink) {
        stepLaunchAnimation()
    }

    /// Switches the panel into a drag-friendly mode where mouse events pass
    /// through so System Settings can receive the drop destination interaction.
    func setDraggingPassthrough(_ isDragging: Bool) {
        ignoresMouseEvents = isDragging
        alphaValue = isDragging ? 0.72 : 1.0
        if isDragging {
            orderBack(nil)
        } else {
            orderFrontRegardless()
        }
    }

    /// Repositions the panel under the latest tracked System Settings frame.
    /// While the launch animation is still running, only the destination is
    /// updated so the motion stays continuous.
    func snap(to settingsFrame: CGRect) {
        let target = targetFrame(for: settingsFrame)
        if isAnimatingLaunch {
            // Tracking updates can arrive during the launch. Updating the final
            // destination preserves the motion instead of abruptly snapping.
            launchTargetFrame = target
            return
        }

        stopLaunchAnimation()
        finishLaunch(at: target)
    }

    /// Calculates the final panel frame relative to the System Settings window.
    /// The panel aligns to the trailing content area, stays underneath the
    /// window, and is clamped to the visible frame of the matching screen.
    private func targetFrame(for settingsFrame: CGRect) -> CGRect {
        let screenFrame = NSScreen.screens
            .first(where: { $0.frame.intersects(settingsFrame) })?
            .visibleFrame ?? settingsFrame

        // The helper panel is anchored to the trailing content area of System
        // Settings rather than the full window width because the leading
        // sidebar is not the user's active target.
        let contentMinX = settingsFrame.minX + sidebarWidth
        let availableContentWidth = max(240, settingsFrame.width - sidebarWidth)
        let width = min(availableContentWidth, screenFrame.width - (screenInset * 2))
        let height = measuredPanelHeight(for: width)

        // This is the place to tune visual attachment if the panel feels too
        // far from the bottom edge of System Settings.
        //
        // Current behavior:
        //   y = settingsFrame.minY - height
        // means "place the panel immediately below the tracked window frame".
        //
        // If the tracked frame still includes some visual framing/shadow, the
        // panel will look separated by that amount. A manual tweak such as:
        //
        //   y = settingsFrame.minY - height + 28
        //
        // is effectively saying "treat the bottom 28pt as non-visual spacing
        // and pull the panel upward".
        //
        // This is usually a better place for that adjustment than
        // SettingsWindowTracker.appKitScreenFrame(...), because the intent here
        // is clearly visual alignment of the floating panel, not coordinate
        // conversion of the tracked window.
        var origin = CGPoint(
            x: contentMinX,
            y: settingsFrame.minY - height
        )

        origin.x = max(screenFrame.minX + screenInset, min(origin.x, screenFrame.maxX - width - screenInset))
        origin.y = max(screenFrame.minY + screenInset, min(origin.y, screenFrame.maxY - height - screenInset))

        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    /// Measures the SwiftUI content at a specific width so the panel height can
    /// fit its dynamic contents before being positioned or animated.
    private func measuredPanelHeight(for width: CGFloat) -> CGFloat {
        sizingView.setFrameSize(NSSize(width: width, height: sizingHeightLimit))
        sizingView.layoutSubtreeIfNeeded()
        return max(minimumPanelHeight, sizingView.fittingSize.height)
    }

    /// Advances the launch motion. Only the window origin moves and the content
    /// layer scales — the window keeps its final size, so there is no SwiftUI
    /// relayout per step.
    private func stepLaunchAnimation() {
        guard isAnimatingLaunch else { return }

        let elapsed = max(0, CACurrentMediaTime() - launchStartTime)
        if elapsed >= animationDuration {
            finishLaunch(at: launchTargetFrame)
            return
        }

        let progress = springProgress(at: elapsed)
        alphaValue = initialAlpha + ((1 - initialAlpha) * progress)
        applyContentScale(minimumLaunchScale + ((1 - minimumLaunchScale) * progress))

        let targetCenter = CGPoint(x: launchTargetFrame.midX, y: launchTargetFrame.midY)
        let center = curvedCenter(from: launchSourceCenter, to: targetCenter, progress: progress)
        setFrameOrigin(CGPoint(
            x: center.x - (launchTargetFrame.width * 0.5),
            y: center.y - (launchTargetFrame.height * 0.5)
        ))
    }

    /// Lands the panel at its destination: full size, identity scale, shadow and
    /// opacity restored. Also used as the no-animation fast path.
    private func finishLaunch(at target: CGRect) {
        stopLaunchAnimation()
        isAnimatingLaunch = false
        setFrame(target, display: false)
        applyContentScale(1)
        alphaValue = 1
        hasShadow = true
        orderFrontRegardless()
    }

    /// Stops and clears whichever ticker drives the launch animation.
    private func stopLaunchAnimation() {
        launchTimer?.invalidate()
        launchTimer = nil
        if #available(macOS 14.0, *) {
            (displayLink as? CADisplayLink)?.invalidate()
        }
        displayLink = nil
    }

    /// Produces a smooth eased progress value for the launch motion so the
    /// panel accelerates and settles without a harsh linear stop.
    private func springProgress(at elapsed: TimeInterval) -> CGFloat {
        let omega = (2 * Double.pi) / animationResponse
        let progress = 1 - exp(-omega * elapsed) * (1 + (omega * elapsed))
        return min(max(progress, 0), 1)
    }

    /// Interpolates the panel center along a quadratic Bezier path for a softer
    /// "fly to target" arc than a straight linear interpolation.
    private func curvedCenter(from startCenter: CGPoint, to endCenter: CGPoint, progress: CGFloat) -> CGPoint {
        let midpoint = CGPoint(
            x: (startCenter.x + endCenter.x) * 0.5,
            y: max(startCenter.y, endCenter.y)
        )
        let distance = hypot(endCenter.x - startCenter.x, endCenter.y - startCenter.y)
        let lift = min(140, max(44, distance * 0.18))
        let controlPoint = CGPoint(x: midpoint.x, y: midpoint.y + lift)
        let inverse = 1 - progress
        return CGPoint(
            x: (inverse * inverse * startCenter.x) + (2 * inverse * progress * controlPoint.x) + (progress * progress * endCenter.x),
            y: (inverse * inverse * startCenter.y) + (2 * inverse * progress * controlPoint.y) + (progress * progress * endCenter.y)
        )
    }

    private static func makePanelView(
        controller: PermissionFlowController,
        localeIdentifier: String?
    ) -> AnyView {
        let view = PermissionFlowPanelView(controller: controller)
        guard let localeIdentifier else { return AnyView(view) }
        return AnyView(view.environment(\.locale, .init(identifier: localeIdentifier)))
    }
}
#endif
