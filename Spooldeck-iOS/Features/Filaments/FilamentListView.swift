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
            Screen {
                filterBar
                if filaments.isEmpty {
                    if !query.isEmpty {
                        EmptyState(systemImage: "magnifyingglass", title: "No results for “\(query)”", message: "Check the spelling or try a different search.")
                    } else {
                        EmptyState(
                            systemImage: "swatchpalette",
                            title: showArchived ? "No archived filaments" : "No filaments yet",
                            message: "A filament is a product, like “Prusament PLA Galaxy Black”. Spools are the physical rolls of it."
                        ) {
                            if !showArchived {
                                Button("Add your first filament") { showNew = true }.buttonStyle(.spoolPrimary)
                            }
                        }
                    }
                } else {
                    DividedRows(data: filaments) { filament in
                        NavigationLink(value: Route.filament(id: filament.id)) {
                            FilamentRowView(filament: filament)
                        }
                        .buttonStyle(RowLinkStyle())
                        .accessibilityIdentifier("filamentRow")
                    }
                    .cardStyle(padding: 0)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                }
            }
        }
        .navigationTitle(showArchived ? "Archived" : "Filaments")
        .searchable(text: $query, prompt: "Name, color, brand, material")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !materials.isEmpty {
                    Menu {
                        Picker("Material", selection: $materialId) {
                            Text("All materials").tag(Int?.none)
                            ForEach(materials) { Text($0.name).tag(Int?.some($0.id)) }
                        }
                    } label: {
                        FilterChip(title: materials.first { $0.id == materialId }?.name ?? "All materials", isActive: materialId != nil)
                    }
                }
                if !brands.isEmpty {
                    Menu {
                        Picker("Brand", selection: $brandId) {
                            Text("All brands").tag(Int?.none)
                            ForEach(brands) { Text($0.name).tag(Int?.some($0.id)) }
                        }
                    } label: {
                        FilterChip(title: brands.first { $0.id == brandId }?.name ?? "All brands", isActive: brandId != nil)
                    }
                }
                Menu {
                    Picker("Show", selection: $showArchived) {
                        Text("Active").tag(false)
                        Text("Archived").tag(true)
                    }
                } label: {
                    FilterChip(title: showArchived ? "Archived" : "Active", isActive: showArchived)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
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
            VStack(alignment: .leading, spacing: 2) {
                Text(filament.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(([filament.brandName, filament.materialName].compactMap { $0 } + ["\(Format.field(filament.diameter)) mm"]).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(1)
                if let rating = filament.rating, rating > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                        Text("\(rating)")
                    }
                    .font(.caption2)
                    .foregroundStyle(Theme.mutedForeground)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.grams(max(0, filament.remaining)))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("\(filament.activeCount) in stock" + (filament.spoolCount > filament.activeCount ? " · \(filament.spoolCount - filament.activeCount) used up" : ""))
                    .font(.caption)
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Theme.spacing)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// Highlight for rows inside a card, like a native cell.
struct RowLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.muted : Color.clear)
    }
}
