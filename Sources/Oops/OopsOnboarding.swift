import SwiftUI

/// Layout note: the prototype uses fixed 1920×1080 absolute coordinates. Here we keep
/// the same *composition* (passthrough behind, a centered glass window/card, a right-edge
/// sidebar, bottom page-dots + home-pill) but let SwiftUI lay it out responsively so it
/// runs on the iPad / Vision Pro simulators the project targets.

// MARK: - 01 · Opening

struct OpeningScreen: View {
    let onBegin: () -> Void
    @State private var breathe = false

    var body: some View {
        ZStack {
            OopsPassthrough()
            HStack {
                Spacer()
                WorldWindow()
                    .frame(maxWidth: 980, maxHeight: 620)
                Spacer()
            }
            .padding(.horizontal, 60)

            VStack {
                Spacer()
                Text("Tap anywhere to begin")
                    .oopsSub(20)
                    .opacity(breathe ? 0.95 : 0.45)
                    .padding(.bottom, 120)
                PageDots().padding(.bottom, 18)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onBegin)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

// MARK: - 02 · Home

struct HomeScreen: View {
    let onGenerate: () -> Void
    let onVisitOld: () -> Void

    var body: some View {
        ZStack {
            OopsPassthrough()
            HStack {
                Spacer()
                WorldWindow {
                    VStack {
                        Spacer()
                        HStack(spacing: 32) {
                            Button("Generate New", action: onGenerate)
                                .buttonStyle(OopsButton())
                            Button("Visit Old World", action: onVisitOld)
                                .buttonStyle(OopsButton())
                        }
                        .padding(.bottom, 54)
                    }
                }
                .frame(maxWidth: 980, maxHeight: 620)
                Spacer()
            }
            .padding(.horizontal, 60)

            VStack {
                Spacer()
                PageDots().padding(.bottom, 18)
            }
        }
    }
}

/// The framed "generated world" preview pane on Opening / Home. Uses `oops_meadow`
/// as a stand-in (the prototype's `villa.png` wasn't included in the asset bundle).
private struct WorldWindow<Overlay: View>: View {
    @ViewBuilder var overlay: Overlay
    init(@ViewBuilder overlay: () -> Overlay = { EmptyView() }) { self.overlay = overlay() }

    var body: some View {
        ZStack {
            Image("oops_meadow")
                .resizable()
                .scaledToFill()
            LinearGradient(colors: [.clear, .black.opacity(0.35)],
                           startPoint: .center, endPoint: .bottom)
            overlay
        }
        .clipShape(RoundedRectangle(cornerRadius: OopsGlass.radiusWindow, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OopsGlass.radiusWindow, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 40, y: 26)
    }
}

// MARK: - 03 / 04 · Declaration (Safety & Privacy)

struct DeclarationScreen: View {
    let label: String
    let title: String
    let items: [OopsContent.Statement]
    let cta: String
    @Binding var checks: [Bool]
    let onCta: () -> Void

    private var allChecked: Bool { checks.allSatisfy { $0 } }

    var body: some View {
        ZStack {
            OopsPassthrough(dim: true)

            VStack(spacing: 30) {
                VStack(spacing: 30) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(title).oopsTitle(34)
                        Text(OopsContent.declarationIntro)
                            .oopsSub(20)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 22) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            CheckStatement(head: item.head, text: item.text,
                                           checked: checks[i]) { checks[i].toggle() }
                        }
                    }
                }
                .padding(.vertical, 46)
                .padding(.horizontal, 56)
                .frame(maxWidth: 900)
                .oopsCard()

                Button(cta, action: onCta)
                    .buttonStyle(OopsButton())
                    .disabled(!allChecked)
                    .opacity(allChecked ? 1 : 0.4)
                    .animation(.easeInOut(duration: 0.2), value: allChecked)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 60)

            VStack { Spacer(); PageDots().padding(.bottom, 18) }
        }
    }
}
