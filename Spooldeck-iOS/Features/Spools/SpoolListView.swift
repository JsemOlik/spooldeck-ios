import SwiftUI

struct SpoolFilter: Hashable {
    enum Sort: String, CaseIterable, Identifiable {
        case name, remaining, recent, used
        var id: String { rawValue }
        var label: String {
            switch self {
            case .name: "Name"
            case .remaining: "Least remaining"
            case .recent: "Recently added"
            case .used: "Recently used"
            }
        }
    }

    /// "active", "all" or a SpoolStatus raw value, as the API expects.
    var status = "active"
    var materialId: Int?
    var brandId: Int?
    var filamentId: Int?
    var location: String?
    var lowOnly = false
    var sort: Sort = .name

    var isFiltered: Bool {
        status != "active" || materialId != nil || brandId != nil || filamentId != nil || location != nil || lowOnly
    }
}

/// A spool as a card, like the web's SpoolCard.
struct SpoolCardView: View {
    let spool: SpoolRow
    var lowStock: Double?

    private var isLow: Bool {
        spool.status != .empty && lowStock.map { spool.remaining <= $0 } == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ColorSwatch(hex: spool.colorHex, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(spool.subtitle.isEmpty ? "Unknown" : spool.subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.mutedForeground)
                    Text(spool.title)
                        .font(.body.weight(.medium))
                    if spool.colorName != nil {
                        Text(spool.filamentName)
                            .font(.caption)
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                StatusBadge(status: spool.status)
            }
            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.grams(max(0, spool.remaining)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isLow ? Theme.destructive : .primary)
                    Spacer()
                    Text("of \(Format.grams(spool.initialWeight))")
                        .font(.caption)
                        .foregroundStyle(Theme.mutedForeground)
                }
                .monospacedDigit()
                RemainingBar(initial: spool.initialWeight, remaining: spool.remaining, low: isLow)
            }
            HStack {
                Text("#\(spool.code)").monospaced()
                Spacer()
                if let location = spool.location { LocationLabel(location: location) }
            }
            .font(.caption)
            .foregroundStyle(Theme.mutedForeground)
        }
        .cardStyle()
        .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
}

struct SpoolListView: View {
    @Environment(AppModel.self) private var app
    @State private var filter: SpoolFilter
    @State private var query = ""
    @State private var spools: [SpoolRow]?
    @State private var error: Error?
    @State private var lowStock: Double?
    @State private var materials: [Material] = []
    @State private var brands: [Brand] = []
    @State private var locations: [Location] = []
    @State private var showNewSpool = false

    init(initialFilter: SpoolFilter? = nil) {
        _filter = State(initialValue: initialFilter ?? SpoolFilter())
    }

    var body: some View {
        LoadingView(value: spools, error: error, retry: load) { spools in
            Screen {
                filterBar
                if spools.isEmpty {
                    emptyState
                } else {
                    Text(summary(spools))
                        .font(.subheadline)
                        .foregroundStyle(Theme.mutedForeground)
                    LazyVStack(spacing: 12) {
                        ForEach(spools) { spool in
                            NavigationLink(value: Route.spool(id: spool.id)) {
                                SpoolCardView(spool: spool, lowStock: lowStock)
                            }
                            .buttonStyle(CardLinkStyle())
                            .accessibilityIdentifier("spoolCard")
                        }
                    }
                }
            }
        }
        .navigationTitle(filter.lowOnly ? "Running low" : "Spools")
        .searchable(text: $query, prompt: "Search color, brand, code, location…")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let spools, !spools.isEmpty {
                    Button("Print labels", systemImage: "tag") { app.labelSpoolIds = spools.map(\.id) }
                }
                Button("Add spool", systemImage: "plus") { showNewSpool = true }
            }
        }
        .sheet(isPresented: $showNewSpool) {
            NavigationStack { SpoolFormView(mode: .create(filamentId: filter.filamentId)) }
        }
        .task(id: TaskKey(filter: filter, query: query, version: app.dataVersion)) {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled else { return }
            await load()
        }
        .task { await loadFilterOptions() }
        .refreshable { await load() }
    }

    private struct TaskKey: Equatable {
        let filter: SpoolFilter
        let query: String
        let version: Int
    }

    private func summary(_ spools: [SpoolRow]) -> String {
        let grams = spools.filter { $0.status.isActive }.reduce(0) { $0 + max(0, $1.remaining) }
        let count = spools.count == 1 ? "1 spool" : "\(spools.count) spools"
        return "\(count) · \(Format.grams(grams)) of filament"
    }

    @ViewBuilder
    private var emptyState: some View {
        if !query.isEmpty {
            EmptyState(systemImage: "magnifyingglass", title: "No results for “\(query)”", message: "Check the spelling or try a different search.")
        } else if filter.isFiltered {
            EmptyState(systemImage: "line.3.horizontal.decrease", title: "No matching spools", message: "Try different filters.") {
                Button("Clear filters") { filter = SpoolFilter(sort: filter.sort) }
                    .buttonStyle(.spoolOutline)
            }
        } else {
            EmptyState(systemImage: "shippingbox", title: "No spools yet", message: "Add a spool or scan a Prusament QR code.") {
                Button("Add spool", systemImage: "plus") { showNewSpool = true }
                    .buttonStyle(.spoolPrimary)
            }
        }
    }

    /// Dropdowns like the web's filter row, scrolling sideways on narrow screens.
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !materials.isEmpty {
                    Menu {
                        Picker("Material", selection: $filter.materialId) {
                            Text("All materials").tag(Int?.none)
                            ForEach(materials) { Text($0.name).tag(Int?.some($0.id)) }
                        }
                    } label: {
                        FilterChip(title: materials.first { $0.id == filter.materialId }?.name ?? "All materials", isActive: filter.materialId != nil)
                    }
                }
                if !brands.isEmpty {
                    Menu {
                        Picker("Brand", selection: $filter.brandId) {
                            Text("All brands").tag(Int?.none)
                            ForEach(brands) { Text($0.name).tag(Int?.some($0.id)) }
                        }
                    } label: {
                        FilterChip(title: brands.first { $0.id == filter.brandId }?.name ?? "All brands", isActive: filter.brandId != nil)
                    }
                }
                if !locations.isEmpty {
                    Menu {
                        Picker("Location", selection: $filter.location) {
                            Text("All locations").tag(String?.none)
                            ForEach(locations) { Text($0.name).tag(String?.some($0.name)) }
                        }
                    } label: {
                        FilterChip(title: filter.location ?? "All locations", isActive: filter.location != nil)
                    }
                }
                Menu {
                    Picker("Status", selection: $filter.status) {
                        Text("In stock").tag("active")
                        ForEach(SpoolStatus.allCases) { Text($0 == .opened ? "Open" : $0.label).tag($0.rawValue) }
                        Text("All").tag("all")
                    }
                    Toggle("Running low only", isOn: $filter.lowOnly)
                } label: {
                    FilterChip(title: statusTitle, isActive: filter.status != "active" || filter.lowOnly)
                }
                Menu {
                    Picker("Sort", selection: $filter.sort) {
                        ForEach(SpoolFilter.Sort.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    FilterChip(title: "Sort: \(filter.sort.label.lowercased())")
                }
                if filter.isFiltered {
                    Button("Clear", systemImage: "xmark") { filter = SpoolFilter(sort: filter.sort) }
                        .buttonStyle(.spool(.ghost, compact: true))
                }
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
    }

    private var statusTitle: String {
        let base = switch filter.status {
        case "active": "In stock"
        case "all": "All"
        case "opened": "Open"
        default: SpoolStatus(rawValue: filter.status)?.label ?? "In stock"
        }
        return filter.lowOnly ? "\(base) · low" : base
    }

    private func load() async {
        do {
            let response: SpoolsResponse = try await app.api.get("spools", query: [
                "q": query,
                "status": filter.status,
                "materialId": filter.materialId.map(String.init),
                "brandId": filter.brandId.map(String.init),
                "filamentId": filter.filamentId.map(String.init),
                "location": filter.location,
                "sort": filter.sort.rawValue,
                "low": filter.lowOnly ? "1" : nil,
            ])
            spools = response.spools
            error = nil
        } catch is CancellationError {
        } catch let urlError as APIError where (urlError.isCancellation) {
        } catch {
            if spools == nil { self.error = error }
        }
    }

    private func loadFilterOptions() async {
        async let m: ItemsResponse<Material>? = try? app.api.get("catalog/materials")
        async let b: ItemsResponse<Brand>? = try? app.api.get("catalog/brands")
        async let l: LocationsResponse? = try? app.api.get("locations")
        async let s: AppSettings? = try? app.api.get("settings")
        materials = await m?.items.filter { ($0.filaments ?? 0) > 0 } ?? []
        brands = await b?.items.filter { ($0.filaments ?? 0) > 0 } ?? []
        locations = await l?.locations ?? []
        lowStock = await s.map { Double($0.lowStockGrams) }
    }
}

/// Press feedback for tappable cards: dims and shrinks slightly, like a native cell highlight.
struct CardLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension APIError {
    var isCancellation: Bool {
        if case .network(let error) = self { return (error as? URLError)?.code == .cancelled }
        return false
    }
}
