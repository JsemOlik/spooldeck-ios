import SwiftUI

enum CatalogKind: String, Identifiable {
    case materials, brands, vendors
    var id: String { rawValue }

    var title: String {
        switch self {
        case .materials: "Materials"
        case .brands: "Brands"
        case .vendors: "Shops"
        }
    }

    var singular: String {
        switch self {
        case .materials: "material"
        case .brands: "brand"
        case .vendors: "shop"
        }
    }
}

/// One editable row of any catalog kind, decoded loosely so a single list view handles all three.
struct CatalogItem: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let website: String?
    let url: String?
    let notes: String?
    let density: Double?
    let nozzleMin: Int?
    let nozzleMax: Int?
    let bedMin: Int?
    let bedMax: Int?
    let filaments: Int?
    let spools: Int?

    func detail(for kind: CatalogKind) -> String {
        switch kind {
        case .materials:
            var parts = ["\(Format.field(density)) g/cm³"]
            let nozzle = Format.range(nozzleMin, nozzleMax)
            if nozzle != "—" { parts.append("nozzle \(nozzle)") }
            let bed = Format.range(bedMin, bedMax)
            if bed != "—" { parts.append("bed \(bed)") }
            return parts.joined(separator: " · ")
        case .brands:
            return website ?? ""
        case .vendors:
            return url ?? notes ?? ""
        }
    }

    func usage(for kind: CatalogKind) -> String {
        if kind == .vendors {
            let n = spools ?? 0
            return "\(n) spool\(n == 1 ? "" : "s")"
        }
        let n = filaments ?? 0
        return "\(n) filament\(n == 1 ? "" : "s")"
    }
}

struct CatalogListView: View {
    @Environment(AppModel.self) private var app
    let kind: CatalogKind

    @State private var items: [CatalogItem]?
    @State private var error: Error?
    @State private var editing: Editing?
    @State private var toDelete: CatalogItem?
    @State private var actionError: String?

    struct Editing: Identifiable {
        let item: CatalogItem?
        var id: String { item.map { String($0.id) } ?? "new" }
    }

    var body: some View {
        LoadingView(value: items, error: error, retry: load) { items in
            List {
                if items.isEmpty {
                    Text("No \(kind.title.lowercased()) yet.").foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    Button {
                        editing = Editing(item: item)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).foregroundStyle(.primary)
                                let detail = item.detail(for: kind)
                                if !detail.isEmpty {
                                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            Text(item.usage(for: kind)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { toDelete = item }
                    }
                }
            }
            .themedForm()
        }
        .navigationTitle(kind.title)
        .toolbar {
            Button("Add", systemImage: "plus") { editing = Editing(item: nil) }
        }
        .sheet(item: $editing) { editing in
            NavigationStack { CatalogItemForm(kind: kind, item: editing.item) }
        }
        .confirmationDialog("Delete “\(toDelete?.name ?? "")”?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible, presenting: toDelete) { item in
            Button("Delete", role: .destructive) { Task { await delete(item) } }
        } message: { item in
            Text("Anything using this \(kind.singular) keeps its data but loses the link (\(item.usage(for: kind))).")
        }
        .alert("Couldn't delete", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .task(id: app.dataVersion) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            let response: ItemsResponse<CatalogItem> = try await app.api.get("catalog/\(kind.rawValue)")
            items = response.items
            error = nil
        } catch {
            if items == nil { self.error = error }
        }
    }

    private func delete(_ item: CatalogItem) async {
        do {
            try await app.api.delete("catalog/\(kind.rawValue)/\(item.id)")
            app.didMutate()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

struct CatalogItemForm: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let kind: CatalogKind
    let item: CatalogItem?

    @State private var name = ""
    @State private var link = ""
    @State private var notes = ""
    @State private var density = "1.24"
    @State private var nozzleMin = ""
    @State private var nozzleMax = ""
    @State private var bedMin = ""
    @State private var bedMax = ""
    @State private var fieldErrors: [String: [String]] = [:]
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                FieldErrorText(errors: fieldErrors, field: "name")
                switch kind {
                case .brands:
                    TextField("Website", text: $link).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    FieldErrorText(errors: fieldErrors, field: "website")
                case .vendors:
                    TextField("Website", text: $link).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    FieldErrorText(errors: fieldErrors, field: "url")
                case .materials:
                    NumberField("Density", text: $density, unit: "g/cm³")
                    FieldErrorText(errors: fieldErrors, field: "density")
                }
            }
            if kind == .materials {
                Section("Default temperatures") {
                    HStack {
                        Text("Nozzle")
                        Spacer()
                        TextField("min", text: $nozzleMin).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 56)
                        Text("–")
                        TextField("max", text: $nozzleMax).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 56)
                    }
                    FieldErrorText(errors: fieldErrors, field: "nozzleMax")
                    HStack {
                        Text("Bed")
                        Spacer()
                        TextField("min", text: $bedMin).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 56)
                        Text("–")
                        TextField("max", text: $bedMax).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 56)
                    }
                    FieldErrorText(errors: fieldErrors, field: "bedMax")
                }
            }
            if kind != .brands {
                Section("Notes") {
                    TextField(kind == .vendors ? "Shipping times, discount codes…" : "Notes", text: $notes, axis: .vertical)
                }
            }
            if let error {
                Section { Text(error).foregroundStyle(Theme.destructive) }
            }
        }
        .themedForm()
        .navigationTitle(item == nil ? "New \(kind.singular)" : "Edit \(kind.singular)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }.disabled(name.isEmpty || isSaving)
            }
        }
        .onAppear(perform: prefill)
    }

    private func prefill() {
        guard let item, name.isEmpty else { return }
        name = item.name
        link = item.website ?? item.url ?? ""
        notes = item.notes ?? ""
        density = Format.field(item.density ?? 1.24)
        nozzleMin = Format.field(item.nozzleMin)
        nozzleMax = Format.field(item.nozzleMax)
        bedMin = Format.field(item.bedMin)
        bedMax = Format.field(item.bedMax)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var body: FormBody = ["name": name]
        switch kind {
        case .brands:
            body["website"] = link
        case .vendors:
            body["url"] = link
            body["notes"] = notes
        case .materials:
            body["density"] = density.decimalNormalized
            body["nozzleMin"] = nozzleMin
            body["nozzleMax"] = nozzleMax
            body["bedMin"] = bedMin
            body["bedMax"] = bedMax
            body["notes"] = notes
        }
        do {
            if let item {
                let _: MutationResult = try await app.api.put("catalog/\(kind.rawValue)/\(item.id)", body: body)
            } else {
                let _: MutationResult = try await app.api.post("catalog/\(kind.rawValue)", body: body)
            }
            app.didMutate()
            dismiss()
        } catch let apiError as APIError {
            fieldErrors = apiError.fieldErrors
            error = apiError.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct LocationsView: View {
    @Environment(AppModel.self) private var app
    @State private var locations: [Location]?
    @State private var error: Error?
    @State private var renaming: Location?
    @State private var newName = ""

    var body: some View {
        LoadingView(value: locations, error: error, retry: load) { locations in
            List {
                if locations.isEmpty {
                    Text("Set a location on a spool and it shows up here.").foregroundStyle(.secondary)
                }
                ForEach(locations) { location in
                    HStack {
                        NavigationLink(value: Route.spools(filter: SpoolFilter(status: "all", location: location.name))) {
                            LabeledContent(location.name, value: "\(location.spools) spool\(location.spools == 1 ? "" : "s")")
                        }
                    }
                    .swipeActions {
                        Button("Rename", systemImage: "pencil") {
                            newName = location.name
                            renaming = location
                        }
                        .tint(Theme.primary)
                    }
                }
            }
            .themedForm()
        }
        .navigationTitle("Locations")
        .alert("Rename location", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { location in
            TextField("Name", text: $newName)
            Button("Rename") { Task { await rename(location) } }
            Button("Cancel", role: .cancel) {}
        } message: { location in
            Text("Applies to all \(location.spools) spools. Leave it empty to clear the location.")
        }
        .task(id: app.dataVersion) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            let response: LocationsResponse = try await app.api.get("locations")
            locations = response.locations
            error = nil
        } catch {
            if locations == nil { self.error = error }
        }
    }

    private func rename(_ location: Location) async {
        let _: MutationResult? = try? await app.api.post("locations/rename", body: ["from": location.name, "name": newName])
        app.didMutate()
    }
}
