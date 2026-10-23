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

        Screen {
            HStack(alignment: .top, spacing: 16) {
                if let image = f.imageUrl, let url = URL(string: image) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            ColorSwatch(hex: f.colorHex, size: 72)
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    ColorSwatch(hex: f.colorHex, size: 72)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(([f.brand?.name, f.material?.name].compactMap { $0 } + ["\(Format.field(f.diameter)) mm"]).joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(Theme.mutedForeground)
                    Text(f.title).font(.title.weight(.semibold)).lineLimit(2)
                    HStack(spacing: 8) {
                        if f.colorName != nil {
                            Text(f.name).font(.subheadline).foregroundStyle(Theme.mutedForeground).lineLimit(1)
                        }
                        RatingView(rating: f.rating)
                        if f.archived { OutlineTag(text: "Archived") }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 4)

            HStack(spacing: 8) {
                Button("Add spool", systemImage: "plus") { sheet = .newSpool }
                    .buttonStyle(.spool(.primary, fullWidth: true))
                if let link = f.productUrl, let url = URL(string: link) {
                    Link(destination: url) { Label("Product page", systemImage: "arrow.up.right.square") }
                        .buttonStyle(.spool(.outline, fullWidth: true))
                }
                actionsMenu(d)
            }

            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    StatCard(title: "In stock", value: Format.grams(inStock), detail: active.count == 1 ? "1 spool" : "\(active.count) spools")
                    StatCard(title: "Used so far", value: Format.grams(usedSoFar), detail: printUsage.count == 1 ? "1 print logged" : "\(printUsage.count) prints logged")
                }
                GridRow {
                    StatCard(title: "Avg price", value: averagePerKg.map { Format.money($0, currency: currency) } ?? "—", detail: "per kg")
                    StatCard(title: "Spools bought", value: "\(d.spools.count)", detail: d.spools.first?.vendor.map { "last from \($0.name)" } ?? " ")
                }
            }

            Card("Notes") {
            } trailing: {
                Button("Add note", systemImage: "square.and.pencil") { sheet = .addNote }
                    .buttonStyle(.spool(.outline, compact: true))
            } content: {
                if d.notes.isEmpty {
                    Text("No notes yet.").font(.subheadline).foregroundStyle(Theme.mutedForeground)
                } else {
                    VStack(spacing: 10) {
                        ForEach(d.notes) { note in
                            NoteRow(note: note) { Task { await deleteNote(note) } }
                        }
                    }
                }
            }

            Card("Spools & purchases") {
                if d.spools.isEmpty {
                    Text("No spools yet.").font(.subheadline).foregroundStyle(Theme.mutedForeground)
                } else {
                    DividedRows(data: d.spools) { spool in
                        NavigationLink(value: Route.spool(id: spool.id)) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text("#\(spool.code)").font(.subheadline.weight(.medium)).monospaced()
                                        StatusBadge(status: spool.status)
                                    }
                                    Text([spool.purchaseDate.map { Format.day($0) }, spool.vendor?.name, spool.location].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(Theme.mutedForeground)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                if let price = spool.price {
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(Format.money(price, currency: spool.currency ?? currency)).font(.subheadline)
                                        Text("\(Format.money(price / max(spool.initialWeight, 1) * 1000, currency: spool.currency ?? currency))/kg")
                                            .font(.caption)
                                            .foregroundStyle(Theme.mutedForeground)
                                    }
                                    .monospacedDigit()
                                }
                                Text(Format.grams(max(0, spool.remaining)))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .frame(minWidth: 64, alignment: .trailing)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Card("Print settings") {
                SpecList(items: [
                    ("Nozzle", Format.range(f.effectiveNozzle.0, f.effectiveNozzle.1)),
                    ("Bed", Format.range(f.effectiveBed.0, f.effectiveBed.1)),
                    ("Drying", f.dryingTemp.map { t in "\(t) °C" + (f.dryingHours.map { " · \(Format.field($0)) h" } ?? "") }),
                    ("Max speed", f.maxSpeed.map { "\($0) mm/s" }),
                    ("Fan", f.fan),
                    ("Density", f.material.map { "\(Format.field($0.density)) g/cm³" }),
                ])
            }

            Card("Spool") {
                SpecList(items: [
                    ("Net weight", Format.grams(f.nominalWeight)),
                    ("Empty spool", f.spoolWeight.map { Format.grams($0) }),
                    ("Diameter", "\(Format.field(f.diameter)) mm"),
                    ("Color", f.colorHex),
                ])
            }
        }
    }

    private func actionsMenu(_ d: FilamentDetail) -> some View {
        Menu {
            Button("Edit", systemImage: "pencil") { sheet = .edit }
            if !d.spools.isEmpty {
                Button("Print labels", systemImage: "tag") {
                    app.labelSpoolIds = d.spools.filter { $0.status.isActive }.map(\.id)
                }
            }
            Button(d.filament.archived ? "Unarchive" : "Archive", systemImage: "archivebox") {
                Task { await setArchived(!d.filament.archived) }
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
        } label: {
            IconButtonLabel(systemImage: "ellipsis")
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("More actions")
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
