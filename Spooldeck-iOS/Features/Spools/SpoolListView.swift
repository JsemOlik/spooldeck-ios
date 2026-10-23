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

struct SpoolRowView: View {
    let spool: SpoolRow
    var lowStock: Double?

    var body: some View {
        HStack(spacing: 12) {
            ColorSwatch(hex: spool.colorHex)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(spool.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(Format.grams(spool.remaining))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(lowStock.map { spool.remaining <= $0 } == true ? .orange : .primary)
                }
                HStack {
                    Text(spool.subtitle)
                    Spacer()
                    Text("#\(spool.code)").monospaced()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                RemainingBar(initial: spool.initialWeight, remaining: spool.remaining, lowStock: lowStock)
                if spool.status != .opened || spool.location != nil {
                    HStack(spacing: 6) {
                        if spool.status != .opened { StatusBadge(status: spool.status) }
                        if let location = spool.location {
                            Label(location, systemImage: "mappin")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
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

    private let isRoot: Bool

    init(initialFilter: SpoolFilter? = nil) {
        _filter = State(initialValue: initialFilter ?? SpoolFilter())
        isRoot = initialFilter == nil
    }

    var body: some View {
        LoadingView(value: spools, error: error, retry: load) { spools in
            if spools.isEmpty {
                if !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ContentUnavailableView {
                        Label(filter.isFiltered ? "No matching spools" : "No spools yet", systemImage: "circle.circle")
                    } description: {
                        Text(filter.isFiltered ? "Try different filters." : "Add a spool or scan a Prusament QR code.")
                    } actions: {
                        if filter.isFiltered {
                            Button("Clear filters") { filter = SpoolFilter(sort: filter.sort) }
                        }
                    }
                }
            } else {
                List(spools) { spool in
                    NavigationLink(value: Route.spool(id: spool.id)) {
                        SpoolRowView(spool: spool, lowStock: lowStock)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(filter.lowOnly ? "Running low" : "Spools")
        .searchable(text: $query, prompt: "Color, brand, code, location…")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                filterMenu
                Menu {
                    Button("New spool", systemImage: "plus") { showNewSpool = true }
                    if let spools, !spools.isEmpty {
                        Button("Print labels for these", systemImage: "printer") {
                            app.labelSpoolIds = spools.map(\.id)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
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

    private var filterMenu: some View {
        Menu {
            Picker("Sort", selection: $filter.sort) {
                ForEach(SpoolFilter.Sort.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)

            Picker("Status", selection: $filter.status) {
                Text("In stock").tag("active")
                ForEach(SpoolStatus.allCases) { Text($0.label).tag($0.rawValue) }
                Text("All").tag("all")
            }
            .pickerStyle(.menu)

            Toggle("Running low only", isOn: $filter.lowOnly)

            if !materials.isEmpty {
                Picker("Material", selection: $filter.materialId) {
                    Text("Any material").tag(Int?.none)
                    ForEach(materials) { Text($0.name).tag(Int?.some($0.id)) }
                }
                .pickerStyle(.menu)
            }
            if !brands.isEmpty {
                Picker("Brand", selection: $filter.brandId) {
                    Text("Any brand").tag(Int?.none)
                    ForEach(brands) { Text($0.name).tag(Int?.some($0.id)) }
                }
                .pickerStyle(.menu)
            }
            if !locations.isEmpty {
                Picker("Location", selection: $filter.location) {
                    Text("Anywhere").tag(String?.none)
                    ForEach(locations) { Text($0.name).tag(String?.some($0.name)) }
                }
                .pickerStyle(.menu)
            }
            if filter.isFiltered {
                Button("Clear filters", systemImage: "xmark.circle", role: .destructive) {
                    filter = SpoolFilter(sort: filter.sort)
                }
            }
        } label: {
            Image(systemName: filter.isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter and sort")
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

extension APIError {
    var isCancellation: Bool {
        if case .network(let error) = self { return (error as? URLError)?.code == .cancelled }
        return false
    }
}
