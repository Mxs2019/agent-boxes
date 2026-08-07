import SwiftUI
import UIKit

enum EmptyDeckPhotos {
    static let names = [
        "EmptyPeacePalm",
        "EmptyPeaceLake",
        "EmptyPeaceLeaves",
        "EmptyPeaceWater",
    ]

    static func name(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return names[day % names.count]
    }
}

struct EmptyDeckView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var touch = CGPoint(x: 0.5, y: 0.5)
    @State private var touchIntensity: CGFloat = 0
    private let photoNameOverride: String?
    private let bottomContentInset: CGFloat
    private let artworkOpacity: Double
    private let showsContent: Bool
    private let openHistory: () -> Void

    init(
        photoName: String? = nil,
        bottomContentInset: CGFloat = 0,
        artworkOpacity: Double = 1,
        showsContent: Bool = true,
        openHistory: @escaping () -> Void = {}
    ) {
        photoNameOverride = photoName
        self.bottomContentInset = bottomContentInset
        self.artworkOpacity = artworkOpacity
        self.showsContent = showsContent
        self.openHistory = openHistory
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                model.themeColor.appBackgroundColor

                artwork(size: geometry.size)
                    .opacity(artworkOpacity)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.08), .black.opacity(0.62)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .opacity(artworkOpacity)
                .allowsHitTesting(false)

                EstimatedTouchSurface {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                } onChanged: { location, intensity in
                    touch = location
                    touchIntensity = intensity
                } onEnded: {
                    withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) {
                        touch = CGPoint(x: 0.5, y: 0.5)
                        touchIntensity = 0
                    }
                }
                .allowsHitTesting(showsContent)
                .accessibilityHidden(true)

                VStack(spacing: 14) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .frame(width: 52, height: 52)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay { Circle().strokeBorder(.white.opacity(0.32), lineWidth: 1) }
                        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)

                    Text("All clear")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Everything is reviewed.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.82))

                    Button {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        openHistory()
                    } label: {
                        Label(
                            "View history",
                            systemImage: CardTimelineSection.history.systemImage
                        )
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 1)
                    }
                    .accessibilityHint("Shows reviewed cards.")
                    .accessibilityIdentifier("empty-history-button")
                    .padding(.top, 4)
                }
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.3), radius: 12, y: 3)
                .padding(.horizontal, 28)
                .padding(
                    .bottom,
                    max(geometry.safeAreaInsets.bottom + 34, 52) + bottomContentInset
                )
                .opacity(showsContent ? 1 : 0)
                .offset(y: showsContent || reduceMotion ? 0 : 52)
                .scaleEffect(showsContent || reduceMotion ? 1 : 0.94, anchor: .bottom)
                .allowsHitTesting(showsContent)
                .accessibilityHidden(!showsContent)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("All clear. Everything is reviewed.")
        .accessibilityIdentifier("empty-deck")
        .accessibilityHidden(!showsContent)
    }

    private var photoName: String {
        photoNameOverride ?? EmptyDeckPhotos.name(for: Date())
    }

    private func artwork(size: CGSize) -> some View {
        let pausesAnimation = reduceMotion || (artworkOpacity <= 0 && !showsContent)
        return TimelineView(.animation(minimumInterval: 1 / 30, paused: pausesAnimation)) { context in
            photo(size: size, date: context.date)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }

    private func photo(size: CGSize, date: Date) -> some View {
        let time = reduceMotion ? 0 : date.timeIntervalSinceReferenceDate

        return Image(photoName)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
            .distortionEffect(
                ShaderLibrary.emptyDeckRipple(
                    .float2(size.width, size.height),
                    .float(Float(time.truncatingRemainder(dividingBy: 10_000))),
                    .float2(Float(touch.x), Float(touch.y)),
                    .float(Float(touchIntensity))
                ),
                maxSampleOffset: CGSize(width: 28, height: 28)
            )
            .colorEffect(
                ShaderLibrary.emptyDeckField(
                    .float2(size.width, size.height),
                    .float(Float(time.truncatingRemainder(dividingBy: 10_000))),
                    .float2(Float(touch.x), Float(touch.y)),
                    .color(model.themeColor.color),
                    .float(colorScheme == .dark ? 1 : 0),
                    .float(Float(touchIntensity))
                )
            )
    }
}

private struct EstimatedTouchSurface: UIViewRepresentable {
    let onBegan: () -> Void
    let onChanged: (CGPoint, CGFloat) -> Void
    let onEnded: () -> Void

    func makeUIView(context: Context) -> EstimatedTouchView {
        let view = EstimatedTouchView()
        update(view)
        return view
    }

    func updateUIView(_ view: EstimatedTouchView, context: Context) {
        update(view)
    }

    static func dismantleUIView(_ view: EstimatedTouchView, coordinator: Void) {
        view.cancelTracking()
    }

    private func update(_ view: EstimatedTouchView) {
        view.onBegan = onBegan
        view.onChanged = onChanged
        view.onEnded = onEnded
    }
}

private final class EstimatedTouchView: UIView {
    var onBegan: (() -> Void)?
    var onChanged: ((CGPoint, CGFloat) -> Void)?
    var onEnded: (() -> Void)?

    private var activeTouch: UITouch?
    private var displayLink: CADisplayLink?
    private var initialRadius: CGFloat = 1
    private var currentRadius: CGFloat = 1
    private var currentLocation = CGPoint.zero
    private var previousLocation = CGPoint.zero
    private var previousTimestamp: TimeInterval = 0
    private var startTime: CFTimeInterval = 0
    private var movementSpeed: CGFloat = 0
    private var displayedIntensity: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }

        activeTouch = touch
        currentLocation = touch.location(in: self)
        previousLocation = currentLocation
        previousTimestamp = touch.timestamp
        initialRadius = max(touch.majorRadius, 1)
        currentRadius = initialRadius
        movementSpeed = 0
        displayedIntensity = 0
        startTime = CACurrentMediaTime()
        startDisplayLink()
        onBegan?()
        updateTouch(touch)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch,
              let touch = touches.first(where: { $0 === activeTouch })
        else { return }
        updateTouch(touch)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch, touches.contains(where: { $0 === activeTouch }) else { return }
        finishTracking()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch, touches.contains(where: { $0 === activeTouch }) else { return }
        finishTracking()
    }

    func cancelTracking() {
        guard activeTouch != nil else {
            stopDisplayLink()
            return
        }
        finishTracking()
    }

    private func updateTouch(_ touch: UITouch) {
        let location = touch.location(in: self)
        let elapsed = max(touch.timestamp - previousTimestamp, 1 / 120)
        let distance = hypot(
            location.x - previousLocation.x,
            location.y - previousLocation.y
        )
        movementSpeed = distance / elapsed
        currentLocation = location
        currentRadius = max(touch.majorRadius, 1)
        previousLocation = location
        previousTimestamp = touch.timestamp
        emitEstimate()
    }

    @objc private func displayLinkDidFire() {
        movementSpeed *= 0.82
        emitEstimate()
    }

    private func emitEstimate() {
        let radiusRatio = currentRadius / initialRadius
        let contactArea = clamped((radiusRatio - 0.92) / 0.48)
        let holdDuration = clamped(CGFloat(CACurrentMediaTime() - startTime) / 1.2)
        let movement = clamped(movementSpeed / 800)
        let steadiness = (1 - movement) * holdDuration
        let target = clamped(
            0.08
                + contactArea * 0.52
                + holdDuration * 0.25
                + steadiness * 0.15
                - movement * 0.12
        )
        displayedIntensity += (target - displayedIntensity) * 0.22

        let normalizedLocation = CGPoint(
            x: clamped(currentLocation.x / max(bounds.width, 1)),
            y: clamped(currentLocation.y / max(bounds.height, 1))
        )
        onChanged?(normalizedLocation, displayedIntensity)
    }

    private func startDisplayLink() {
        stopDisplayLink()
        let displayLink = CADisplayLink(target: self, selector: #selector(displayLinkDidFire))
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: 30,
            maximum: 60,
            preferred: 60
        )
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func finishTracking() {
        activeTouch = nil
        stopDisplayLink()
        onEnded?()
    }

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}
