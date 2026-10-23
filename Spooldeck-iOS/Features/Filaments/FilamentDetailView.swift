import SwiftUI

struct FilamentDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let filamentId: Int

    @State private var detail: FilamentDetail?
    @State private var error: Error?
    @State private var sheet: Sheet?
    @State private var confirmDelete = false
    @State private var actionError: String?

    enum Sheet: String, Identifiable {
        case edit, newSpool, addNote
        var id: String { rawValue }
    }

    var body: some View {
        LoadingView(value: detail, error: error, retry: load) { detail in
            content(detail)
        }
        .navigationTitle(detail?.filament.title ?? "Filament")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if let detail { toolbar(detail) } }
        .task(id: app.dataVersion) { await load() }
        .refreshable { await load() }
        .sheet(item: $sheet) { sheet in
            if let detail {
                NavigationStack {
                    switch sheet {
                    case .edit: FilamentFormView(filament: detail.filament)
                    case .newSpool: SpoolFormView(mode: .create(filamentId: detail.id))
                    case .addNote: NoteComposer(filamentId: detail.id)
                    }
                }
            }
        }
        .confirmationDialog("Delete this filament?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete filament", role: .destructive) { Task { await deleteFilament() } }
        } message: {
            Text("Only filaments without spools can be deleted. Archive it to hide it instead.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    @ViewBuilder
    private func content(_ d: FilamentDetail) -> some View {
        let f = d.filament
        let active = d.spools.filter { $0.status.isActive }
        let inStock = active.reduce(0) { $0 + max(0, $1.remaining) }
        let printUsage = d.spools.flatMap(\.usage).filter { $0.kind == .print }
        let usedSoFar = d.spools.reduce(0) { $0 + $1.used }
        let priced = d.spools.filter { $0.price != nil }
        let currency = priced.first?.currency ?? "EUR"
        let averagePerKg: Double? = priced.isEmpty ? nil
            : priced.reduce(0) { $0 + ($1.price! / max($1.initialWeight, 1)) * 1000 } / Double(priced.count)

        List {
            Section {
                HStack(spacing: 16) {
                    if let image = f.imageUrl, let url = URL(string: image) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                ColorSwatch(hex: f.colorHex, size: 72)
                            }
                        }
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        ColorSwatch(hex: f.colorHex, size: 72)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        if !f.subtitle.isEmpty {
                            Text(f.subtitle).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text(f.title).font(.title2.bold())
                        if f.colorName != nil { Text(f.name).font(.caption).foregroundStyle(.secondary) }
                        RatingView(rating: f.rating)
                        if f.archived {
                            Text("Archived").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                        }
                    }
                }
                Button("Add spool", systemImage: "plus.circle") { sheet = .newSpool }
                if let link = f.productUrl, let url = URL(string: link) {
                    Link(destination: url) { Label("Product page", systemImage: "safari") }
                }
            }

            Section("Stats") {
                LabeledContent("In stock", value: "\(Format.grams(inStock)) · \(active.count) spool\(active.count == 1 ? "" : "s")")
                LabeledContent("Used so far", value: "\(Format.grams(usedSoFar)) · \(printUsage.count) print\(printUsage.count == 1 ? "" : "s")")
                if let averagePerKg {
                    LabeledContent("Average price", value: "\(Format.money(averagePerKg, currency: currency)) / kg")
                }
                LabeledContent("Spools bought", value: "\(d.spools.count)")
            }

            Section {
                ForEach(d.notes) { note in
                    NoteRow(note: note)
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Task { await deleteNote(note) }
                            }
                        }
                }
                Button("Add note", systemImage: "square.and.pencil") { sheet = .addNote }
            } header: {
                Text("Notes")
            }

            if !d.spools.isEmpty {
                Section("Spools") {
                    ForEach(d.spools) { spool in
                        NavigationLink(value: Route.spool(id: spool.id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("#\(spool.code)").monospaced()
                                    StatusBadge(status: spool.status)
                                    Spacer()
                                    Text(Format.grams(spool.remaining)).monospacedDigit()
                                }
                                HStack {
                                    if let vendor = spool.vendor?.name { Text(vendor) }
                                    if let price = spool.price { Text(Format.money(price, currency: spool.currency ?? currency)) }
                                    if let date = spool.purchaseDate { Text(Format.day(date)) }
                                    if let location = spool.location { Label(location, systemImage: "mappin") }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            }
                        }
                    }
                }
            }

            Section("Print settings") {
                LabeledContent("Nozzle", value: Format.range(f.effectiveNozzle.0, f.effectiveNozzle.1))
                LabeledContent("Bed", value: Format.range(f.effectiveBed.0, f.effectiveBed.1))
                InfoRow("Max speed", f.maxSpeed.map { "\($0) mm/s" })
                InfoRow("Fan", f.fan)
                InfoRow("Drying", f.dryingTemp.map { t in "\(t)°C" + (f.dryingHours.map { " · \(Format.field($0)) h" } ?? "") })
                InfoRow("Density", f.material.map { "\(Format.field($0.density)) g/cm³" })
            }

            Section("Spool specs") {
                LabeledContent("Diameter", value: "\(Format.field(f.diameter)) mm")
                LabeledContent("Net weight", value: Format.grams(f.nominalWeight))
                InfoRow("Empty spool", f.spoolWeight.map { Format.grams($0) })
            }
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ d: FilamentDetail) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Edit", systemImage: "pencil") { sheet = .edit }
                Button("Add spool", systemImage: "plus.circle") { sheet = .newSpool }
                if !d.spools.isEmpty {
                    Button("Print labels", systemImage: "printer") {
                        app.labelSpoolIds = d.spools.filter { $0.status.isActive }.map(\.id)
                    }
                }
                Button(d.filament.archived ? "Unarchive" : "Archive", systemImage: "archivebox") {
                    Task { await setArchived(!d.filament.archived) }
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private func load() async {
        do {
            detail = try await app.api.get("filaments/\(filamentId)")
            error = nil
        } catch {
            if detail == nil { self.error = error }
        }
    }

    private func setArchived(_ archived: Bool) async {
        do {
            let _: MutationResult = try await app.api.post("filaments/\(filamentId)/archive", body: ["archived": archived ? "true" : "false"])
            app.didMutate()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func deleteNote(_ note: FilamentNote) async {
        do {
            try await app.api.delete("notes/\(note.id)")
            app.didMutate()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func deleteFilament() async {
        do {
            try await app.api.delete("filaments/\(filamentId)")
            dismiss()
            app.didMutate()
        } catch {
            actionError = error.localizedDescription
        }
    }
}
