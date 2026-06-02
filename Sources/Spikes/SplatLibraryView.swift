import SwiftUI

// ⚠️ DEV ONLY — the dev-menu entry point for the splat feature. Lets you generate a
// new World Labs world from a prompt (walking straight into the resulting splat) and
// reopen previously generated worlds. The history list is "hard-coded seeds + worlds
// auto-accumulated on each successful generation" (persisted locally). Not for shipping.

// MARK: - Local store

/// A World Labs world that was generated on this device. Persisted so the dev menu can
/// reopen its walkable splat without regenerating (which costs ~5 min + paid credits).
struct SavedSplatWorld: Codable, Identifiable {
    let id: String        // world_id from the API
    let name: String      // the prompt it was generated from (truncated for display)
    let spzURL: URL       // public CDN .spz URL
    let createdAt: Date
}

/// UserDefaults-backed list of generated worlds (dev-only convenience).
enum SplatLibrary {
    private static let key = "splat.library.v1"

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
}

enum SplatSeeds {
    static let all: [SeedSplatWorld] = [
        SeedSplatWorld(id: "world_a236ea24",
                       name: "Sample world (a236ea24)",
                       source: .bundled(resource: SplatSpikeDebug.bundledSplat))
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
                                    spzURL: spzURL,
                                    createdAt: Date())
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
                Button { route = .remote(world.spzURL) } label: {
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

    @State private var service = WorldLabsService()
    @State private var prompt = "A cozy artisan's workshop with wooden workbenches, hanging tools, and warm afternoon light through a window"
    @State private var saved: [SavedSplatWorld] = SplatLibrary.load()
    /// Shown when a generation finished without a splat URL, or a bundled seed is missing.
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                generateSection
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
                                    spzURL: spzURL,
                                    createdAt: Date())
        SplatLibrary.add(world)
        saved = SplatLibrary.load()
        enter(spzURL)
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
                Button { open(seed.source) } label: {
                    worldRow(title: seed.name, subtitle: "Sample · \(seed.id)")
                }
            }

            ForEach(saved) { world in
                Button { enter(world.spzURL) } label: {
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

    /// Resolves a seed's source to a URL and opens the walkable world. Bundled seeds
    /// resolve to their packaged `.spz`; remote seeds pass their CDN URL straight through.
    private func open(_ source: SeedSource) {
        switch source {
        case .bundled(let resource):
            guard let url = Bundle.main.url(forResource: resource, withExtension: "spz") else {
                errorMessage = "Bundled \(resource).spz not found"
                return
            }
            enter(url)
        case .remote(let url):
            enter(url)
        }
    }

    /// Opens the CompositorServices full-immersion splat space. `SplatVisionRenderer`
    /// downloads + caches remote URLs, so both bundled files and CDN URLs work here.
    private func enter(_ url: URL) {
        errorMessage = nil
        Task { await openImmersiveSpace(id: "splat", value: url) }
    }
}

#endif
