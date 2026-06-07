import SwiftUI
import UniformTypeIdentifiers

// ⚠️ DEV ONLY — the dev-menu entry point for the splat feature. Lets you generate a
// new World Labs world from a prompt (walking straight into the resulting splat) and
// reopen previously generated worlds. The history list is "hard-coded seeds + worlds
// auto-accumulated on each successful generation" (persisted locally). Not for shipping.

// MARK: - Local store

/// A walkable splat the dev menu can reopen without redoing the work to get it: either
/// a World Labs world generated on this device (its CDN `.spz`), or a `.spz` imported
/// from the Files app (copied into `Documents/ImportedSplats`). Persisted locally.
struct SavedSplatWorld: Codable, Identifiable {
    let id: String        // world_id (generated) or filename (imported)
    let name: String      // the prompt / the file's display name
    let createdAt: Date
    /// marble/raw exports load upside-down; remembered so reopening keeps the fix.
    var flipUpsideDown: Bool = false
    /// World Labs generated worlds: the public CDN `.spz` URL.
    var remoteURL: URL? = nil
    /// Imported worlds: filename under `SplatImporter.importedDir()` (stored relative
    /// so the sandbox path changing between launches doesn't break the reference).
    var localFilename: String? = nil

    /// The URL to hand the renderer: rebuilds the local path from Documents each time,
    /// else the remote CDN URL.
    func resolvedURL() -> URL? {
        if let localFilename { return SplatImporter.importedDir().appendingPathComponent(localFilename) }
        return remoteURL
    }
}

/// UserDefaults-backed list of generated + imported worlds (dev-only convenience).
enum SplatLibrary {
    // v2: schema gained flip / remoteURL / localFilename (old v1 data is ignored).
    private static let key = "splat.library.v2"

    static func load() -> [SavedSplatWorld] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let worlds = try? JSONDecoder().decode([SavedSplatWorld].self, from: data)
        else { return [] }
        return worlds
    }

    /// Insert at the front, de-duplicating by world id (newest wins).
    static func add(_ world: SavedSplatWorld) {
        var worlds = load().filter { $0.id != world.id }
        worlds.insert(world, at: 0)
        save(worlds)
    }

    static func remove(id: String) {
        save(load().filter { $0.id != id })
    }

    private static func save(_ worlds: [SavedSplatWorld]) {
        if let data = try? JSONEncoder().encode(worlds) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Hard-coded seeds

/// Where a seed world's splat comes from: a bundled `.spz` (works offline) or a remote
/// CDN URL (downloaded on demand).
enum SeedSource {
    case bundled(resource: String)
    case remote(URL)
}

/// A known world that always appears in the list. Currently just the bundled spike
/// asset; add more entries here once their spz URL is known.
struct SeedSplatWorld: Identifiable {
    let id: String
    let name: String
    let source: SeedSource
    /// Raw marble exports load upside-down and need a 180° flip; the bundled sample
    /// is already upright. Defaults to upright so existing entries are unaffected.
    var flipUpsideDown: Bool = false
    /// Bundle resource base-names of the USDZ objects to float inside this world (arranged
    /// in a ring in front of the start viewpoint). Empty → renderer uses its demo fallback.
    var modelNames: [String] = []
}

/// What the splat immersive space needs to render a world: where the `.spz` is, whether it
/// must be flipped upright, and which USDZ objects to overlay. Passed as the `"splat"`
/// space's value (visionOS).
struct SplatEntry: Codable, Hashable {
    let url: URL
    var flipUpsideDown: Bool = false
    /// Bundle resource base-names of USDZ objects to composite into the world. Empty → the
    /// renderer falls back to its single bundled demo model (legacy behaviour).
    var modelNames: [String] = []
}

enum SplatSeeds {
    // V3 demo: the bundled "Vibrant Loft Art Studio" marble world plus the two
    // personality worlds (Extroverted / Introverted), each carrying its own USDZ objects.
    // All three are raw marble exports — they load upside-down and need a 180° flip.
    static let all: [SeedSplatWorld] = [
        SeedSplatWorld(id: "vibrant_loft_art_studio",
                       name: "Vibrant Loft Art Studio",
                       source: .bundled(resource: "vibrant_loft_art_studio"),
                       flipUpsideDown: true),
        SeedSplatWorld(id: "extroverted_world",
                       name: "Extroverted",
                       source: .bundled(resource: "Extroverted_world"),
                       flipUpsideDown: true,
                       modelNames: ["MacBook_Neo", "Coeur_Amoureux", "Jack_Daniel", "Backpack"]),
        SeedSplatWorld(id: "introverted_world",
                       name: "Introverted",
                       source: .bundled(resource: "Introverted_world"),
                       flipUpsideDown: true,
                       modelNames: ["Unseen_Fancy_Mirror", "Coffee_Cup", "Globe",
                                    "Book_animated_book__historical_book", "Hour_Glass",
                                    "Candles_set"])
    ]
}

#if !os(visionOS)

// MARK: - Library screen

/// Navigation route into a walkable splat scene.
private enum SplatRoute: Hashable {
    case bundled(resource: String)
    case remote(URL)
}

/// DEV-only dev-menu entry: generate a world from a prompt or reopen a previous one,
/// then walk into its splat. Reuses `WorldLabsService` for generation and
/// `SplatWorldView` / `SplatSceneView` for rendering.
struct SplatLibraryView: View {
    /// Returns to the dev menu. Surfaced as the list root's leading toolbar item
    /// so the container can omit its floating back button (no double back).
    let onClose: () -> Void

    @State private var service = WorldLabsService()
    @State private var prompt = "A cozy artisan's workshop with wooden workbenches, hanging tools, and warm afternoon light through a window"
    @State private var route: SplatRoute?
    @State private var saved: [SavedSplatWorld] = SplatLibrary.load()
    /// Shown when a generation finished but yielded no walkable splat URL.
    @State private var generateError: String?

    var body: some View {
        NavigationStack {
            List {
                generateSection
                historySection
            }
            .navigationTitle("Splat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Back to menu")
                }
            }
            .navigationDestination(item: $route) { route in
                destination(for: route)
            }
            .onChange(of: service.status) { _, newValue in
                if case .ready = newValue { handleGenerated() }
            }
        }
    }

    // MARK: Generate

    private var generateSection: some View {
        Section("Generate a new world") {
            TextField("Describe a world", text: $prompt, axis: .vertical)
                .lineLimit(2...4)
                .disabled(isBusy)

            statusBody

            if let generateError {
                Text(generateError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button(isBusy ? "Generating…" : "Generate world") {
                generateError = nil
                Task { await service.run(prompt: prompt) }
            }
            .disabled(isBusy || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private var statusBody: some View {
        switch service.status {
        case .idle:
            Text("Generation takes ~5 minutes and uses paid API credits.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .generating(let progress):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: Double(progress), total: 100)
                    .animation(.linear(duration: 6), value: progress)
                Text("Building your world… \(progress)%  (~5 min)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .downloading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Downloading…").font(.footnote).foregroundStyle(.secondary)
            }
        case .failed(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
        case .ready:
            EmptyView()
        }
    }

    /// On a successful generation, persist the new world (if it has a splat URL) and
    /// walk straight into it. The panorama produced by `run` is ignored here.
    private func handleGenerated() {
        guard let spzURL = service.splatRemoteURL, let worldId = service.worldId else {
            generateError = "World generated but no splat (.spz) URL was available."
            return
        }
        let world = SavedSplatWorld(id: worldId,
                                    name: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                                    createdAt: Date(),
                                    remoteURL: spzURL)
        SplatLibrary.add(world)
        saved = SplatLibrary.load()
        route = .remote(spzURL)
    }

    private var isBusy: Bool {
        switch service.status {
        case .generating, .downloading: return true
        default: return false
        }
    }

    // MARK: History

    @ViewBuilder
    private var historySection: some View {
        Section("Previously generated") {
            ForEach(SplatSeeds.all) { seed in
                Button { route = route(for: seed.source) } label: {
                    worldRow(title: seed.name, subtitle: "Sample · \(seed.id)")
                }
            }

            ForEach(saved) { world in
                Button {
                    if let url = world.resolvedURL() { route = .remote(url) }
                } label: {
                    worldRow(title: world.name.isEmpty ? world.id : world.name,
                             subtitle: world.id)
                }
            }
            .onDelete(perform: deleteSaved)
        }
    }

    private func worldRow(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func deleteSaved(_ offsets: IndexSet) {
        for index in offsets { SplatLibrary.remove(id: saved[index].id) }
        saved = SplatLibrary.load()
    }

    private func route(for source: SeedSource) -> SplatRoute {
        switch source {
        case .bundled(let resource): return .bundled(resource: resource)
        case .remote(let url):       return .remote(url)
        }
    }

    // MARK: Destination

    @ViewBuilder
    private func destination(for route: SplatRoute) -> some View {
        switch route {
        case .bundled(let resource):
            if let url = Bundle.main.url(forResource: resource, withExtension: "spz") {
                SplatSceneView(splatFileURL: url)
            } else {
                Text("Bundled \(resource).spz not found").padding()
            }
        case .remote(let url):
            SplatWorldView(remoteURL: url)
        }
    }
}

#else

// MARK: - Library screen (visionOS)

/// DEV-only dev-menu entry: generate a world from a prompt or reopen a previous one,
/// then walk into its splat. Mirrors the iOS `SplatLibraryView` section-for-section,
/// reusing the same shared store (`SplatLibrary` / `SplatSeeds`) and `WorldLabsService`.
/// The only platform difference: a walkable world is opened in the CompositorServices
/// full-immersion space (`openImmersiveSpace(id: "splat", value:)`, rendered by
/// `SplatVisionRenderer`) instead of a navigation push. The renderer downloads + caches
/// remote CDN `.spz` URLs itself, so both bundled and generated worlds open the same way.
struct SplatLibraryView: View {
    /// Returns to the dev menu. Surfaced as the list root's leading toolbar item
    /// so the container can omit its floating back button (no double back).
    let onClose: () -> Void

    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var service = WorldLabsService()
    @State private var prompt = "A cozy artisan's workshop with wooden workbenches, hanging tools, and warm afternoon light through a window"
    @State private var saved: [SavedSplatWorld] = SplatLibrary.load()
    /// Shown when a generation finished without a splat URL, or a bundled seed is missing.
    @State private var errorMessage: String?
    /// Files importer state. `flipImported` defaults on because marble exports load
    /// upside-down; turn it off for an already-upright `.spz`.
    @State private var showImporter = false
    @State private var flipImported = true

    var body: some View {
        NavigationStack {
            List {
                generateSection
                importSection
                historySection
            }
            .navigationTitle("Splat")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Back to menu")
                }
            }
            .onChange(of: service.status) { _, newValue in
                if case .ready = newValue { handleGenerated() }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [UTType(filenameExtension: "spz") ?? .data],
                          allowsMultipleSelection: false) { result in
                handleImport(result)
            }
        }
    }

    // MARK: Load from Files

    private var importSection: some View {
        Section("Load from Files") {
            Toggle("Flip upright (marble export)", isOn: $flipImported)
            Button("Load .spz from Files…") { showImporter = true }
        }
    }

    /// Copies a picked `.spz` into durable storage, remembers it, and walks straight in.
    private func handleImport(_ result: Result<[URL], Error>) {
        errorMessage = nil
        switch result {
        case .success(let urls):
            guard let picked = urls.first else { return }
            do {
                let filename = try SplatImporter.storeImported(picked)
                let world = SavedSplatWorld(id: filename,
                                            name: picked.deletingPathExtension().lastPathComponent,
                                            createdAt: Date(),
                                            flipUpsideDown: flipImported,
                                            localFilename: filename)
                SplatLibrary.add(world)
                saved = SplatLibrary.load()
                if let url = world.resolvedURL() {
                    enter(SplatEntry(url: url, flipUpsideDown: world.flipUpsideDown))
                }
            } catch {
                errorMessage = "Import failed: \(error.localizedDescription)"
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Generate

    private var generateSection: some View {
        Section("Generate a new world") {
            TextField("Describe a world", text: $prompt, axis: .vertical)
                .lineLimit(2...4)
                .disabled(isBusy)

            statusBody

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button(isBusy ? "Generating…" : "Generate world") {
                errorMessage = nil
                Task { await service.run(prompt: prompt) }
            }
            .disabled(isBusy || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private var statusBody: some View {
        switch service.status {
        case .idle:
            Text("Generation takes ~5 minutes and uses paid API credits.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .generating(let progress):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: Double(progress), total: 100)
                    .animation(.linear(duration: 6), value: progress)
                Text("Building your world… \(progress)%  (~5 min)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .downloading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Downloading…").font(.footnote).foregroundStyle(.secondary)
            }
        case .failed(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
        case .ready:
            EmptyView()
        }
    }

    /// On a successful generation, persist the new world (if it has a splat URL) and
    /// walk straight into it. The panorama produced by `run` is ignored here.
    private func handleGenerated() {
        guard let spzURL = service.splatRemoteURL, let worldId = service.worldId else {
            errorMessage = "World generated but no splat (.spz) URL was available."
            return
        }
        let world = SavedSplatWorld(id: worldId,
                                    name: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                                    createdAt: Date(),
                                    remoteURL: spzURL)
        SplatLibrary.add(world)
        saved = SplatLibrary.load()
        enter(SplatEntry(url: spzURL))
    }

    private var isBusy: Bool {
        switch service.status {
        case .generating, .downloading: return true
        default: return false
        }
    }

    // MARK: History

    @ViewBuilder
    private var historySection: some View {
        Section("Previously generated") {
            ForEach(SplatSeeds.all) { seed in
                Button { open(seed) } label: {
                    worldRow(title: seed.name, subtitle: "Sample · \(seed.id)")
                }
            }

            ForEach(saved) { world in
                Button {
                    if let url = world.resolvedURL() {
                        enter(SplatEntry(url: url, flipUpsideDown: world.flipUpsideDown))
                    } else {
                        errorMessage = "World file is missing."
                    }
                } label: {
                    worldRow(title: world.name.isEmpty ? world.id : world.name,
                             subtitle: world.id)
                }
            }
            .onDelete(perform: deleteSaved)
        }
    }

    private func worldRow(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func deleteSaved(_ offsets: IndexSet) {
        for index in offsets { SplatLibrary.remove(id: saved[index].id) }
        saved = SplatLibrary.load()
    }

    // MARK: Enter the immersive splat space

    /// Resolves a seed to a `SplatEntry` (URL + upright flip) and opens the walkable
    /// world. Bundled seeds resolve to their packaged `.spz`; remote seeds pass their
    /// CDN URL straight through.
    private func open(_ seed: SeedSplatWorld) {
        switch seed.source {
        case .bundled(let resource):
            guard let url = Bundle.main.url(forResource: resource, withExtension: "spz") else {
                errorMessage = "Bundled \(resource).spz not found"
                return
            }
            enter(SplatEntry(url: url, flipUpsideDown: seed.flipUpsideDown,
                             modelNames: seed.modelNames))
        case .remote(let url):
            enter(SplatEntry(url: url, flipUpsideDown: seed.flipUpsideDown,
                             modelNames: seed.modelNames))
        }
    }

    /// Opens the CompositorServices full-immersion splat space. `SplatVisionRenderer`
    /// downloads + caches remote URLs, so both bundled files and CDN URLs work here.
    /// On success, show the floating exit-controls window and hide the dev-menu window
    /// so only the world remains; the exit button reverses both.
    private func enter(_ entry: SplatEntry) {
        errorMessage = nil
        Task {
            if case .opened = await openImmersiveSpace(id: "splat", value: entry) {
                openWindow(id: "splat-controls")
                dismissWindow(id: "dev-menu")
            } else {
                errorMessage = "Couldn't open the world."
            }
        }
    }
}

#endif
