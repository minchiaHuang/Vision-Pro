import SwiftUI

// MARK: - Loading-screen slideshow (shown during the ~30s world build)

/// One profile in the loading slideshow: a previous visitor's aspiration, shown as a
/// realistic photo inside the frame and captioned with their age + aspiration — mirroring
/// the reference mock's two-line description box ("AGE 25" / "Athlete").
struct LoadingProfile: Identifiable {
    let id = UUID()
    /// Asset-catalog image name for the photo inside the frame.
    let imageName: String
    /// The visitor's age, shown in the small uppercase eyebrow.
    let age: Int
    /// What they aspire to be — the bold title under the eyebrow.
    let aspiration: String
}

enum LoadingSlideshow {
    /// Pre-defined profiles, each a realistic image representing the aspiration. The photos
    /// are bundled in the asset catalog under the matching `imageName`.
    static let profiles: [LoadingProfile] = [
        .init(imageName: "profile_athlete",   age: 25, aspiration: "Athlete"),
        // Pending photo — re-enable once an image is dropped into profile_musician.imageset.
        // .init(imageName: "profile_musician",  age: 39, aspiration: "Musician"),
        .init(imageName: "profile_ballerina", age: 30, aspiration: "Ballerina"),
        .init(imageName: "profile_tech",      age: 20, aspiration: "Working in Tech"),
        .init(imageName: "profile_doctor",    age: 18, aspiration: "Doctor"),
        .init(imageName: "profile_lawyer",    age: 22, aspiration: "Lawyer"),
        .init(imageName: "profile_swimmer",   age: 28, aspiration: "Swimmer"),
        .init(imageName: "profile_rich_dog",  age: 35, aspiration: "Rich, With Her Dog"),
        .init(imageName: "village home",      age: 45, aspiration: "Village Home"),
    ]
}

/// A horizontal picture frame with a warm wooden border. The frame and its bottom-right
/// description box stay perfectly still while only the photo inside slides from one world
/// to the next, cycling on a timer. Built for the generating interstitial so the ~30s
/// world build feels like flipping through a gallery of other visitors' futures.
struct WoodenFrameSlideshow: View {
    var profiles: [LoadingProfile] = LoadingSlideshow.profiles
    /// Seconds each slide holds before sliding to the next.
    var interval: TimeInterval = 4.5
    /// Width of the framed photo; the frame sizes around it at a 16:9 ratio.
    var width: CGFloat = 880

    @State private var index = 0
    @State private var timer: Timer?

    private var profile: LoadingProfile { profiles[index] }

    var body: some View {
        // The description box sits inside the frame, inset from the lower-right corner over
        // the photo, so it never clips at the screen edge.
        ZStack(alignment: .bottomTrailing) {
            woodenFrame
            descriptionBox
                .padding(.trailing, 36)
                .padding(.bottom, 36)
        }
        .onAppear(perform: start)
        .onDisappear { timer?.invalidate() }
    }

    // MARK: Frame + sliding photo

    private var woodenFrame: some View {
        let photoWidth = width
        let photoHeight = width * 9.0 / 16.0
        let border = width * 0.022       // wooden border thickness

        return ZStack {
            // The photo, clipped to the inner opening. Keyed by `index` so each change
            // animates in from the right and the old one slides off to the left.
            ZStack {
                Image(profile.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: photoWidth, height: photoHeight)
                    .clipped()
                    .id(index)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal:   .move(edge: .leading).combined(with: .opacity)))
            }
            .frame(width: photoWidth, height: photoHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            // A faint inner shadow line where the photo meets the wood (the rabbet).
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.black.opacity(0.28), lineWidth: 2))
        }
        .padding(border)
        .background(woodGradient)
        .clipShape(RoundedRectangle(cornerRadius: border * 0.7, style: .continuous))
        // Two highlight/shadow rings give the flat fill a carved, beveled wooden edge.
        .overlay(
            RoundedRectangle(cornerRadius: border * 0.7, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1))
        .overlay(
            RoundedRectangle(cornerRadius: border * 0.7, style: .continuous)
                .strokeBorder(.black.opacity(0.30), lineWidth: 1)
                .blur(radius: 1)
                .offset(y: 1))
        .shadow(color: .black.opacity(0.45), radius: 34, y: 22)
    }

    /// Warm pine/oak gradient for the border, lit from the top-left.
    private var woodGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.80, green: 0.64, blue: 0.44),
                Color(red: 0.69, green: 0.52, blue: 0.34),
                Color(red: 0.58, green: 0.42, blue: 0.27),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Static description box

    private var descriptionBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AGE \(profile.age)")
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.45))
            Text(profile.aspiration)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
        }
        // The text crossfades when the photo changes; the box (size/position) holds still.
        .id(index)
        .transition(.opacity)
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .frame(width: 300, alignment: .leading)
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 22, y: 12)
    }

    // MARK: Timer

    private func start() {
        timer?.invalidate()
        guard profiles.count > 1 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.85)) {
                index = (index + 1) % profiles.count
            }
        }
    }
}

// MARK: - Previews

#Preview("Wooden frame slideshow") {
    ZStack {
        Color(red: 0.34, green: 0.31, blue: 0.28).ignoresSafeArea()
        WoodenFrameSlideshow()
    }
    .preferredColorScheme(.dark)
}
