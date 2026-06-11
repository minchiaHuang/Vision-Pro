import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// One completed Future Museum visit, persisted locally so the user can re-enter a world they've
/// already generated — like a game save. The 3D shell (the BA396 hall) is constant; what a visit
/// actually captures is its *contents*: the Curator `story`, the `answers` it was built from, and
/// the painted beat images. Re-entering only sets `museumStory` / `museumAnswers` / `galleryImages`
/// back on `AppState` and reuses the existing world pipeline — no AI is re-run.
struct VisitRecord: Codable, Identifiable, Sendable {
    let id: String              // UUID
    let title: String           // museumAnswers.role (fallback: story.persona, else "Untitled visit")
    let createdAt: Date
    let story: MuseumStory      // already Codable — the beats (caption / narration / tone …)
    let answers: MuseumAnswers  // already Codable
    /// Beat-ordered image filenames under `imageDir()` (aligned to `story.nodes`). An empty string
    /// marks a beat whose painting failed / never landed, keeping the slot so the beat→wall mapping
    /// never shifts.
    let imageFiles: [String]
    /// Library-card thumbnail filename (the elixir beat, downscaled). Empty if it couldn't be made.
    let heroThumb: String

    /// Folder holding this visit's images: `Documents/Visits/<id>/`.
    func imageDir() -> URL { VisitLibrary.imageDir(id: id) }
}

/// UserDefaults-backed index of completed visits, with the heavy image bytes on disk. Mirrors the
/// dev-only `SplatLibrary` pattern (index in UserDefaults, files in Documents) so the app needs no
/// database. The index holds only metadata; each visit's beat PNGs + thumbnail live under
/// `Documents/Visits/<id>/` and are decoded on demand when the visit is reopened.
enum VisitLibrary {
    static let storageKey = "visit.library.v1"

    // MARK: - Index (UserDefaults)

    static func load(from defaults: UserDefaults = .standard,
                     key: String = storageKey) -> [VisitRecord] {
        guard let data = defaults.data(forKey: key),
              let records = try? JSONDecoder().decode([VisitRecord].self, from: data)
        else { return [] }
        return records
    }

    /// Insert at the front, de-duplicating by id (newest wins). Matches `SplatLibrary.add`.
    static func add(_ record: VisitRecord, to defaults: UserDefaults = .standard,
                    key: String = storageKey) {
        var records = load(from: defaults, key: key).filter { $0.id != record.id }
        records.insert(record, at: 0)
        save(records, to: defaults, key: key)
    }

    /// Drop the record from the index AND delete its on-disk image folder.
    static func remove(id: String, from defaults: UserDefaults = .standard,
                       key: String = storageKey) {
        save(load(from: defaults, key: key).filter { $0.id != id }, to: defaults, key: key)
        try? FileManager.default.removeItem(at: imageDir(id: id))
    }

    private static func save(_ records: [VisitRecord], to defaults: UserDefaults, key: String) {
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: key) }
    }

    // MARK: - Image storage (Documents/Visits/<id>/)

    static func visitsRoot() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Visits", isDirectory: true)
    }

    static func imageDir(id: String) -> URL {
        visitsRoot().appendingPathComponent(id, isDirectory: true)
    }

    /// The elixir beat used for the library-card thumbnail: the last "warm"-toned beat, else the
    /// last beat (−1 only when there are no beats at all). Pure so it's unit-testable on its own.
    static func heroIndex(for story: MuseumStory) -> Int {
        story.nodes.lastIndex { $0.tone == "warm" } ?? (story.nodes.count - 1)
    }

    /// Build the index entry for a run with NO images yet — written the moment the user enters the
    /// museum, so a library card appears immediately rather than only after the ~90s painting wait.
    /// `fillImages(id:imageData:)` later writes the paintings + thumbnail and updates this same
    /// record in place. Pure (no I/O), so it's unit-testable.
    static func makeShell(id: String, story: MuseumStory, answers: MuseumAnswers) -> VisitRecord {
        VisitRecord(id: id, title: title(answers: answers, story: story), createdAt: Date(),
                    story: story, answers: answers, imageFiles: [], heroThumb: "")
    }

    /// Card title: the role the visitor wanted to become; fall back to the Curator persona, then a
    /// neutral label, so a card always has a name.
    static func title(answers: MuseumAnswers, story: MuseumStory) -> String {
        [answers.role, story.persona]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Untitled visit"
    }
}

#if canImport(UIKit)
extension VisitLibrary {
    /// Write a finished run's paintings to disk and update its (already-saved, image-less) index
    /// entry in place. `imageData` is the beat-ordered raw bytes from `MuseumGenerator.nodes`
    /// `.map(\.image)` — a nil / empty entry marks a failed beat, kept as an empty slot so the
    /// beat→wall mapping holds. The originals are written verbatim (gpt-image already returns PNG,
    /// so no re-encode); only the elixir thumbnail is re-encoded (downscaled 512px JPEG). The shell
    /// (`makeShell`) supplies id / title / createdAt / story / answers, all preserved. No-op if the
    /// shell was deleted in the meantime.
    static func fillImages(id: String, imageData: [Data?],
                           from defaults: UserDefaults = .standard) {
        guard let shell = load(from: defaults).first(where: { $0.id == id }) else { return }
        let dir = imageDir(id: id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var files: [String] = []
        for (k, data) in imageData.enumerated() {
            guard let data, !data.isEmpty else { files.append(""); continue }
            let name = "beat-\(k).png"
            do { try data.write(to: dir.appendingPathComponent(name)); files.append(name) }
            catch { files.append("") }
        }

        // Thumbnail = the elixir (last warm) beat, downscaled for the library card.
        let hero = heroIndex(for: shell.story)
        var thumbName = ""
        if hero >= 0, hero < imageData.count,
           let data = imageData[hero], let thumb = downscaledJPEG(data, maxDimension: 512) {
            thumbName = "thumb.jpg"
            try? thumb.write(to: dir.appendingPathComponent(thumbName))
        }

        // Update in place: keep id / title / createdAt / story / answers, swap in the images.
        add(VisitRecord(id: shell.id, title: shell.title, createdAt: shell.createdAt,
                        story: shell.story, answers: shell.answers,
                        imageFiles: files, heroThumb: thumbName),
            to: defaults)
    }

    /// Downscale raw image bytes so the longest side is `maxDimension`, re-encoded as JPEG.
    private static func downscaledJPEG(_ data: Data, maxDimension: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let w = image.size.width, h = image.size.height
        guard w > 0, h > 0 else { return nil }
        let scale = min(1, maxDimension / max(w, h))
        let target = CGSize(width: w * scale, height: h * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}

extension VisitRecord {
    /// Beat-ordered gallery images decoded from disk (aligned to `story.nodes`), a dark panel for
    /// any missing beat — fed straight into `AppState.galleryImages` so the walls paint exactly as
    /// they did live, with no generator running.
    func loadGalleryImages() -> [UIImage] {
        let dir = imageDir()
        return (0..<story.nodes.count).map { k in
            let name = k < imageFiles.count ? imageFiles[k] : ""
            if !name.isEmpty,
               let img = UIImage(contentsOfFile: dir.appendingPathComponent(name).path) {
                return img
            }
            return Self.placeholder
        }
    }

    /// The library-card thumbnail (elixir beat), or nil if it was never written.
    func loadThumb() -> UIImage? {
        guard !heroThumb.isEmpty else { return nil }
        return UIImage(contentsOfFile: imageDir().appendingPathComponent(heroThumb).path)
    }

    /// A plain dark panel for a beat whose image is missing (the same neutral fill the live gallery
    /// uses), so a restored wall slot never collapses or shifts the mapping.
    static let placeholder: UIImage = {
        let size = CGSize(width: 1024, height: 1024)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(white: 0.12, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }()
}
#endif
