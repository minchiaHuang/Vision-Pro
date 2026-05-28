#if !os(visionOS)
import SwiftUI

/// SwiftUI overlay joystick used for the 6DoF spike on iOS / iPadOS.
///
/// Bound to a `SIMD2<Float>` in `[-1, 1]` per axis:
/// - `x` positive → right strafe
/// - `y` positive → forward (drag thumb upward)
///
/// Designed to be dropped into a `ZStack` overlay on top of a `RealityView`.
/// Hit testing is constrained to the joystick's own circular area so the
/// surrounding view (e.g. drag-to-look) keeps working when the user touches
/// elsewhere on screen.
struct VirtualJoystick: View {
    @Binding var value: SIMD2<Float>

    var baseDiameter: CGFloat = 130
    var thumbDiameter: CGFloat = 56

    @State private var thumbOffset: CGSize = .zero
    @State private var isActive: Bool = false

    private var maxRadius: CGFloat { (baseDiameter - thumbDiameter) / 2 }

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle().stroke(.white.opacity(0.25), lineWidth: 1)
                )
                .frame(width: baseDiameter, height: baseDiameter)

            Circle()
                .fill(.white.opacity(isActive ? 0.95 : 0.78))
                .overlay(
                    Image(systemName: "circle.dotted")
                        .font(.system(size: thumbDiameter * 0.36, weight: .light))
                        .foregroundStyle(.black.opacity(0.35))
                )
                .frame(width: thumbDiameter, height: thumbDiameter)
                .offset(thumbOffset)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    isActive = true
                    let raw = gesture.translation
                    let length = sqrt(raw.width * raw.width + raw.height * raw.height)
                    let clamped: CGSize
                    if length > maxRadius {
                        let scale = maxRadius / length
                        clamped = CGSize(width: raw.width * scale,
                                         height: raw.height * scale)
                    } else {
                        clamped = raw
                    }
                    thumbOffset = clamped
                    value = SIMD2<Float>(
                        Float(clamped.width / maxRadius),
                        Float(-clamped.height / maxRadius) // drag up = positive y
                    )
                }
                .onEnded { _ in
                    isActive = false
                    value = .zero
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                        thumbOffset = .zero
                    }
                }
        )
        .accessibilityLabel("Walking joystick")
        .accessibilityHint("Drag to move through the scene.")
    }
}
#endif
