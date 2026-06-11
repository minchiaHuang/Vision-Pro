import SwiftUI

/// "Visit Old World" — a game-save-style grid of past Future Museum visits, persisted locally
/// (`VisitLibrary`). Each card shows the elixir thumbnail, the role the visitor wanted to become,
/// and the date. Tapping a card hands it back via `onSelect` (the coordinator restores it onto
/// `AppState` and re-enters the museum — no AI re-run). Empty until the first run finishes.
struct OopsLibraryScreen: View {
    /// A card was tapped — restore + enter this visit.
    let onSelect: (VisitRecord) -> Void
    /// Back to Home.
    let onBack: () -> Void

    @State private var records: [VisitRecord] = []
    /// The card awaiting a delete confirmation (drives the `OopsDialog`).
    @State private var pendingDelete: VisitRecord?

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 300), spacing: 24)]

    var body: some View {
        ZStack(alignment: .topLeading) {
            OopsPassthrough(dim: true)

            VStack(spacing: 26) {
                VStack(spacing: 10) {
                    Text("Worlds You've Visited").oopsTitle(34)
                    Text("Step back into a place you've been before.")
                        .oopsSub(20)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)

                if records.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 24) {
                            ForEach(records) { record in
                                VisitCard(record: record,
                                          onOpen: { onSelect(record) },
                                          onDelete: { pendingDelete = record })
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 40)
                    }
                }
            }
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)

            backButton
        }
        .onAppear { records = VisitLibrary.load() }
        .overlay { deleteConfirmation }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(OopsGlass.label2)
            Text("No worlds yet")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(OopsGlass.label1)
            Text("Generate a world first — once you've visited one, it'll be saved here for you to return to.")
                .oopsSub(19)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Chrome

    private var backButton: some View {
        Button { ButtonClick.play(); onBack() } label: {
            Image(systemName: "chevron.left")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(14)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 20)
        .padding(.top, 20)
        .accessibilityLabel("Back")
    }

    @ViewBuilder
    private var deleteConfirmation: some View {
        if let target = pendingDelete {
            OopsDialog(
                title: "Forget this world?",
                message: "“\(target.title)” and its pictures will be removed from this device. This can't be undone.",
                confirmTitle: "Forget it",
                onConfirm: {
                    VisitLibrary.remove(id: target.id)
                    records = VisitLibrary.load()
                    pendingDelete = nil
                },
                onCancel: { pendingDelete = nil })
        }
    }
}

/// One save-slot card: elixir thumbnail, the role, the date, plus a small remove control.
private struct VisitCard: View {
    let record: VisitRecord
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button { ButtonClick.play(); onOpen() } label: {
            VStack(alignment: .leading, spacing: 0) {
                thumbnail
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(OopsGlass.label1)
                        .lineLimit(1)
                    Text(Self.dateText(record.createdAt))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(OopsGlass.label2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .buttonStyle(.plain)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: OopsGlass.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OopsGlass.radiusCard, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .overlay(alignment: .topTrailing) { deleteButton }
        .hoverEffect()
    }

    private var deleteButton: some View {
        Button { ButtonClick.play(); onDelete() } label: {
            Image(systemName: "trash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(10)
        .accessibilityLabel("Forget this world")
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(0.35))
            if let ui = record.loadThumb() {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "building.columns")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .frame(height: 150)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private static func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}

// MARK: - Previews

#Preview("Library — empty") {
    OopsLibraryScreen(onSelect: { _ in }, onBack: {})
        .preferredColorScheme(.dark)
}
