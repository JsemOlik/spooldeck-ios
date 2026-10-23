import SwiftUI

struct SpoolDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let spoolId: Int
    var openLogUsage = false

    @State private var spool: SpoolDetail?
    @State private var error: Error?
    @State private var sheet: Sheet?
    @State private var confirmDelete = false
    @State private var usageToDelete: UsageLog?
    @State private var actionError: String?
    @State private var didAutoOpen = false

    enum Sheet: String, Identifiable {
        case logUsage, weighIn, edit, newSpool, addNote
        var id: String { rawValue }
    }

    var body: some View {
        LoadingView(value: spool, error: error, retry: load) { spool in
            content(spool)
        }
        .navigationTitle(spool.map { "#\($0.code)" } ?? "Spool")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if let spool { toolbar(spool) } }
        .task(id: app.dataVersion) { await load() }
        .refreshable { await load() }
        .sheet(item: $sheet) { sheet in
            if let spool {
                NavigationStack { sheetContent(sheet, spool: spool) }
            }
        }
        .confirmationDialog("Delete this spool?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete spool", role: .destructive) { Task { await deleteSpool() } }
        } message: {
            Text("Its usage history goes with it. To keep the history, archive the spool instead.")
        }
        .confirmationDialog("Delete this entry?", isPresented: Binding(get: { usageToDelete != nil }, set: { if !$0 { usageToDelete = nil } }), titleVisibility: .visible, presenting: usageToDelete) { usage in
            Button("Delete and add \(Format.grams(usage.grams)) back", role: .destructive) {
                Task { await deleteUsage(usage) }
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ s: SpoolDetail) -> some View {
        let f = s.filament
        List {
            Section {
                HStack(spacing: 16) {
                    ColorSwatch(hex: f.colorHex, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(f.subtitle.isEmpty ? f.name : f.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(f.title)
                            .font(.title2.bold())
                        HStack(spacing: 8) {
                            StatusBadge(status: s.status)
                            if let location = s.location {
                                Label(location, systemImage: "mappin").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                NavigationLink(value: Route.filament(id: f.id)) {
                    Label(f.name, systemImage: "swatchpalette")
                }
            }

            Section("Remaining") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Format.grams(s.remaining, precise: true))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Spacer()
                        Text("≈ \(Format.length(Weights.estimateLengthM(grams: max(0, s.remaining), diameterMm: f.diameter, density: f.density)))")
                            .foregroundStyle(.secondary)
                    }
                    RemainingBar(initial: s.initialWeight, remaining: s.remaining)
                    Text("\(Format.grams(s.used)) used of \(Format.grams(s.initialWeight))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                HStack {
                    Button {
                        sheet = .logUsage
                    } label: {
                        Label("Log usage", systemImage: "minus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        sheet = .weighIn
                    } label: {
                        Label("Weigh in", systemImage: "scalemass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section("History") {
                if s.usage.isEmpty {
                    Text("Nothing logged yet.").foregroundStyle(.secondary)
                }
                ForEach(s.usage) { usage in
                    UsageRow(usage: usage, spool: s)
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { usageToDelete = usage }
                        }
                }
            }

            Section {
                ForEach(s.filamentNotes) { note in
                    NoteRow(note: note)
                }
                Button("Add note", systemImage: "square.and.pencil") { sheet = .addNote }
            } header: {
                Text("Filament notes")
            } footer: {
                if s.filamentNotes.count >= 5 { Text("Showing the latest 5. See the filament for all notes.") }
            }

            if let notes = s.notes, !notes.isEmpty {
                Section("Spool notes") { Text(notes) }
            }

            Section("Print settings") {
                InfoRow("Nozzle", Format.range(f.effectiveNozzle.0, f.effectiveNozzle.1))
                InfoRow("Bed", Format.range(f.effectiveBed.0, f.effectiveBed.1))
                InfoRow("Max speed", f.maxSpeed.map { "\($0) mm/s" })
                InfoRow("Fan", f.fan)
                InfoRow("Drying", f.dryingTemp.map { t in "\(t)°C" + (f.dryingHours.map { " · \(Format.field($0)) h" } ?? "") })
                InfoRow("Diameter", "\(Format.field(f.diameter)) mm")
            }

            Section("Purchase") {
                InfoRow("Price", s.price.map { Format.money($0, currency: s.currencyCode) })
                InfoRow("Per kg", s.pricePerGram.map { Format.money($0 * 1000, currency: s.currencyCode) })
                InfoRow("Shop", s.vendor?.name)
                InfoRow("Purchased", s.purchaseDate.map { Format.day($0) })
                InfoRow("Opened", s.openedAt.map { Format.date($0) })
                InfoRow("Empty spool", s.spoolWeight.map { Format.grams($0) })
                InfoRow("Added", Format.date(s.createdAt))
                if let link = s.purchaseUrl, let url = URL(string: link) {
                    Link(destination: url) { Label("Product page", systemImage: "safari") }
                }
            }

            if s.prusamentSpoolId != nil {
                Section("Prusament data") {
                    InfoRow("Manufactured", s.manufactureDate.map { Format.day($0) })
                    InfoRow("Length", s.lengthM.map { Format.length($0) })
                    InfoRow("Diameter tolerance", s.diameterTolerance.map { "± \(Format.field($0 / 1000)) mm" })
                    InfoRow("Diameter std. dev.", s.diameterSd.map { "\(Format.field($0 / 1000)) mm" })
                    InfoRow("Ovality", s.ovality.map { "\(Format.field($0)) %" })
                }
            }

            Section("Label") {
                VStack(spacing: 12) {
                    if let qr = QRCode.image(for: s.qrUrl) {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 160, height: 160)
                    }
                    Text(s.qrUrl)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                Button("Print label", systemImage: "printer") { app.labelSpoolIds = [s.id] }
                ShareLink(item: s.qrUrl) { Label("Share link", systemImage: "square.and.arrow.up") }
            }
        }
        .onAppear {
            if openLogUsage && !didAutoOpen {
                didAutoOpen = true
                sheet = .logUsage
            }
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ s: SpoolDetail) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Edit", systemImage: "pencil") { sheet = .edit }
                Menu("Set status", systemImage: "flag") {
                    ForEach(SpoolStatus.allCases.filter { $0 != s.status }) { status in
                        Button(status.label) { Task { await setStatus(status) } }
                    }
                }
                Button("New spool of this filament", systemImage: "plus.circle") { sheet = .newSpool }
                Button("Print label", systemImage: "printer") { app.labelSpoolIds = [s.id] }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: Sheet, spool: SpoolDetail) -> some View {
        switch sheet {
        case .logUsage: LogUsageSheet(spool: spool)
        case .weighIn: WeighInSheet(spool: spool)
        case .edit: SpoolFormView(mode: .edit(spool))
        case .newSpool: SpoolFormView(mode: .create(filamentId: spool.filamentId))
        case .addNote: NoteComposer(filamentId: spool.filamentId, spoolId: spool.id)
        }
    }

    // MARK: - Actions

    private func load() async {
        do {
            spool = try await app.api.get("spools/\(spoolId)")
            error = nil
        } catch {
            if spool == nil { self.error = error }
        }
    }

    private func setStatus(_ status: SpoolStatus) async {
        do {
            let _: MutationResult = try await app.api.post("spools/\(spoolId)/status", body: ["status": status.rawValue])
            app.didMutate()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func deleteUsage(_ usage: UsageLog) async {
        do {
            try await app.api.delete("usage/\(usage.id)")
            app.didMutate()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func deleteSpool() async {
        do {
            try await app.api.delete("spools/\(spoolId)")
            dismiss()
            app.didMutate()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private struct UsageRow: View {
    let usage: UsageLog
    let spool: SpoolDetail

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(usage.printName ?? usage.kind.label)
                if let note = usage.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                Text(Format.dateTime(usage.createdAt)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(usage.grams < 0 ? "+\(Format.grams(-usage.grams))" : "−\(Format.grams(usage.grams))")
                    .monospacedDigit()
                    .foregroundStyle(usage.grams < 0 ? .green : .primary)
                if usage.grams > 0, let cost = Weights.cost(grams: usage.grams, price: spool.price, initialWeight: spool.initialWeight) {
                    Text(Format.money(cost, currency: spool.currencyCode))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct NoteRow: View {
    let note: FilamentNote

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.body)
            HStack {
                Text(Format.dateTime(note.createdAt))
                if let spool = note.spool { Text("· #\(spool.code)").monospaced() }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
