import SwiftUI

struct FilamentListView: View {
    @Environment(AppModel.self) private var app
    @State private var filaments: [FilamentRow]?
    @State private var error: Error?
    @State private var query = ""
    @State private var showArchived = false
    @State private var materialId: Int?
    @State private var brandId: Int?
    @State private var materials: [Material] = []
    @State private var brands: [Brand] = []
    @State private var showNew = false

    var body: some View {
        LoadingView(value: filaments, error: error, retry: load) { filaments in
            if filaments.isEmpty {
                if !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ContentUnavailableView {
                        Label(showArchived ? "No archived filaments" : "No filaments yet", systemImage: "swatchpalette")
                    } description: {
                        Text("A filament is a product, like “Prusament PLA Galaxy Black”. Spools are the physical rolls of it.")
                    } actions: {
                        if !showArchived {
                            Button("Add filament") { showNew = true }.buttonStyle(.borderedProminent)
                        }
                    }
                }
            } else {
                List(filaments) { filament in
                    NavigationLink(value: Route.filament(id: filament.id)) {
                        FilamentRowView(filament: filament)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(showArchived ? "Archived" : "Filaments")
        .searchable(text: $query, prompt: "Name, color, brand, material")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Toggle("Show archived", isOn: $showArchived)
                    if !materials.isEmpty {
                        Picker("Material", selection: $materialId) {
                            Text("Any material").tag(Int?.none)
                            ForEach(materials) { Text($0.name).tag(Int?.some($0.id)) }
                        }
                        .pickerStyle(.menu)
                    }
                    if !brands.isEmpty {
                        Picker("Brand", selection: $brandId) {
                            Text("Any brand").tag(Int?.none)
                            ForEach(brands) { Text($0.name).tag(Int?.some($0.id)) }
                        }
                        .pickerStyle(.menu)
                    }
                } label: {
                    let filtered = showArchived || materialId != nil || brandId != nil
                    Image(systemName: filtered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                Button("Add filament", systemImage: "plus") { showNew = true }
            }
        }
        .sheet(isPresented: $showNew) {
            NavigationStack { FilamentFormView(filament: nil) }
        }
        .task(id: "\(query)|\(showArchived)|\(materialId ?? 0)|\(brandId ?? 0)|\(app.dataVersion)") {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled else { return }
            await load()
        }
        .task { await loadFilterOptions() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            let response: FilamentsResponse = try await app.api.get("filaments", query: [
                "q": query,
                "archived": showArchived ? "1" : nil,
                "materialId": materialId.map(String.init),
                "brandId": brandId.map(String.init),
            ])
            filaments = response.filaments
            error = nil
        } catch let apiError as APIError where apiError.isCancellation {
        } catch {
            if filaments == nil { self.error = error }
        }
    }

    private func loadFilterOptions() async {
        async let m: ItemsResponse<Material>? = try? app.api.get("catalog/materials")
        async let b: ItemsResponse<Brand>? = try? app.api.get("catalog/brands")
        materials = await m?.items.filter { ($0.filaments ?? 0) > 0 } ?? []
        brands = await b?.items.filter { ($0.filaments ?? 0) > 0 } ?? []
    }
}

struct FilamentRowView: View {
    let filament: FilamentRow

    var body: some View {
        HStack(spacing: 12) {
            ColorSwatch(hex: filament.colorHex)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(filament.title).font(.headline).lineLimit(1)
                    Spacer()
                    Text(Format.grams(filament.remaining))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(filament.activeCount > 0 ? .primary : .secondary)
                }
                Text(filament.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 10) {
                    let nozzle = Format.range(filament.nozzleMin, filament.nozzleMax)
                    if nozzle != "—" { Label(nozzle, systemImage: "flame") }
                    let bed = Format.range(filament.bedMin, filament.bedMax)
                    if bed != "—" { Label(bed, systemImage: "square.3.layers.3d.bottom.filled") }
                    Spacer()
                    Text(filament.activeCount == 1 ? "1 spool" : "\(filament.activeCount) spools")
                    if filament.spoolCount > filament.activeCount {
                        Text("· \(filament.spoolCount - filament.activeCount) used up")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                RatingView(rating: filament.rating)
            }
        }
        .padding(.vertical, 2)
    }
}
