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
    @State private var lowStock: Double?

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
        .confirmationDialog("Undo this entry?", isPresented: Binding(get: { usageToDelete != nil }, set: { if !$0 { usageToDelete = nil } }), titleVisibility: .visible, presenting: usageToDelete) { usage in
            Button(usage.grams > 0 ? "Undo and add \(Format.grams(usage.grams)) back" : "Undo entry", role: .destructive) {
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
        let remaining = max(0, s.remaining)
        let low = s.status != .empty && lowStock.map { remaining <= $0 } == true
        Screen {
            header(s)
            remainingCard(s, remaining: remaining, low: low)
            historyCard(s)
            notesCard(s)
            if let notes = s.notes, !notes.isEmpty {
                Card("Spool notes") {
                    Text(notes).font(.subheadline).foregroundStyle(Theme.mutedForeground)
                }
            }
            Card("Print settings") {
                SpecList(items: [
                    ("Nozzle", Format.range(f.effectiveNozzle.0, f.effectiveNozzle.1)),
                    ("Bed", Format.range(f.effectiveBed.0, f.effectiveBed.1)),
                    ("Diameter", "\(Format.field(f.diameter)) mm"),
                    ("Drying", f.dryingTemp.map { t in "\(t) °C" + (f.dryingHours.map { " · \(Format.field($0)) h" } ?? "") }),
                    ("Max speed", f.maxSpeed.map { "\($0) mm/s" }),
                    ("Fan", f.fan),
                ])
            }
            Card("Purchase") {
                SpecList(items: [
                    ("Price", s.price.map { Format.money($0, currency: s.currencyCode) }),
                    ("Per kg", s.pricePerGram.map { Format.money($0 * 1000, currency: s.currencyCode) }),
                    ("Bought from", s.vendor?.name),
                    ("Purchased", s.purchaseDate.map { Format.day($0) }),
                    ("Opened", s.openedAt.map { Format.date($0) }),
                    ("Empty spool", s.spoolWeight.map { Format.grams($0) }),
                ])
                if let link = s.purchaseUrl, let url = URL(string: link) {
                    ExternalLink(title: "Product page", url: url)
                }
            }
            if let prusamentId = s.prusamentSpoolId {
                Card("Prusament data") {
                    SpecList(items: [
                        ("Manufactured", s.manufactureDate.map { Format.day($0) }),
                        ("Length", s.lengthM.map { Format.length($0) }),
                        ("Diameter", s.diameterTolerance.map { "\(Format.field(f.diameter)) ± \(Format.field($0 / 1000)) mm" }),
                        ("Diameter σ", s.diameterSd.map { String(format: "%.2f µm", $0) }),
                        ("Ovality", s.ovality.map { String(format: "%.1f %%", $0) }),
                    ])
                    if let url = URL(string: "https://prusament.com/spool/\(prusamentId)/") {
                        ExternalLink(title: "prusament.com", url: url)
                    }
                }
            }
            qrCard(s)
        }
        .onAppear {
            if openLogUsage && !didAutoOpen {
                didAutoOpen = true
                sheet = .logUsage
            }
        }
    }

    private func header(_ s: SpoolDetail) -> some View {
        let f = s.filament
        return HStack(alignment: .top, spacing: 16) {
            ColorSwatch(hex: f.colorHex, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                if !f.subtitle.isEmpty {
                    Text(f.subtitle).font(.subheadline).foregroundStyle(Theme.mutedForeground)
                }
                Text(f.title)
                    .font(.title.weight(.semibold))
                    .lineLimit(2)
                NavigationLink(value: Route.filament(id: f.id)) {
                    HStack(spacing: 4) {
                        Text(f.name).lineLimit(1)
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(Theme.mutedForeground)
                HStack(spacing: 10) {
                    StatusBadge(status: s.status)
                    Text("#\(s.code)").monospaced()
                    if let location = s.location { LocationLabel(location: location) }
                }
                .font(.subheadline)
                .foregroundStyle(Theme.mutedForeground)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private func remainingCard(_ s: SpoolDetail, remaining: Double, low: Bool) -> some View {
        let f = s.filament
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Remaining").font(.subheadline).foregroundStyle(Theme.mutedForeground)
                    Text(Format.grams(remaining, precise: true))
                        .font(.system(size: 42, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(low ? Theme.destructive : .primary)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("≈ \(Format.length(Weights.estimateLengthM(grams: remaining, diameterMm: f.diameter, density: f.density)))")
                    Text("\(Format.grams(s.used, precise: true)) used of \(Format.grams(s.initialWeight, precise: true))")
                }
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Theme.mutedForeground)
                .padding(.bottom, 6)
            }
            RemainingBar(initial: s.initialWeight, remaining: remaining, low: low, height: 10)
            HStack(spacing: 8) {
                Button("Log usage", systemImage: "minus.circle") { sheet = .logUsage }
                    .buttonStyle(.spool(.primary, fullWidth: true))
                Button("Weigh-in", systemImage: "scalemass") { sheet = .weighIn }
                    .buttonStyle(.spool(.outline, fullWidth: true))
                actionsMenu(s)
            }
        }
        .cardStyle()
    }

    private func actionsMenu(_ s: SpoolDetail) -> some View {
        Menu {
            Button("Edit", systemImage: "pencil") { sheet = .edit }
            Menu("Set status", systemImage: "flag") {
                ForEach(SpoolStatus.allCases.filter { $0 != s.status }) { status in
                    Button(status == .opened ? "Open" : status.label) { Task { await setStatus(status) } }
                }
            }
            Button("New spool of this filament", systemImage: "plus.circle") { sheet = .newSpool }
            Button("Print label", systemImage: "tag") { app.labelSpoolIds = [s.id] }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
        } label: {
            IconButtonLabel(systemImage: "ellipsis")
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("More actions")
    }

    private func historyCard(_ s: SpoolDetail) -> some View {
        Card("Usage history") {
            if s.usage.isEmpty {
                Text("Nothing logged yet.").font(.subheadline).foregroundStyle(Theme.mutedForeground)
            } else {
                DividedRows(data: s.usage) { usage in
                    UsageRow(usage: usage, spool: s) { usageToDelete = usage }
                }
            }
        }
    }

    private func notesCard(_ s: SpoolDetail) -> some View {
        Card("Notes for this filament") {
        } trailing: {
            Button("Add note", systemImage: "square.and.pencil") { sheet = .addNote }
                .buttonStyle(.spool(.outline, compact: true))
        } content: {
            if s.filamentNotes.isEmpty {
                Text("No notes yet.").font(.subheadline).foregroundStyle(Theme.mutedForeground)
            } else {
                VStack(spacing: 10) {
                    ForEach(s.filamentNotes) { note in NoteRow(note: note) }
                }
                if s.filamentNotes.count >= 5 {
                    NavigationLink(value: Route.filament(id: s.filamentId)) {
                        Text("All notes →").font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(Theme.primary)
                }
            }
        }
    }

    private func qrCard(_ s: SpoolDetail) -> some View {
        Card("QR code") {
            VStack(spacing: 12) {
                if let qr = QRCode.image(for: s.qrUrl) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                        .frame(width: 150, height: 150)
                        .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Text(s.qrUrl)
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.mutedForeground)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    Button("Print label", systemImage: "tag") { app.labelSpoolIds = [s.id] }
                        .buttonStyle(.spool(.outline, compact: true))
                    ShareLink(item: s.qrUrl) { Label("Share", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.spool(.outline, compact: true))
                }
            }
            .frame(maxWidth: .infinity)
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
        if lowStock == nil {
            let settings: AppSettings? = try? await app.api.get("settings")
            lowStock = settings.map { Double($0.lowStockGrams) }
        }
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
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(usage.printName ?? usage.kind.label)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if usage.kind != .print && usage.printName != nil { OutlineTag(text: usage.kind.label) }
                }
                Text(Format.dateTime(usage.createdAt) + (usage.note.map { " · \($0)" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text((usage.grams > 0 ? "−" : "+") + Format.grams(abs(usage.grams), precise: true))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if usage.grams > 0, let cost = Weights.cost(grams: usage.grams, price: spool.price, initialWeight: spool.initialWeight) {
                    Text(Format.money(cost, currency: spool.currencyCode))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.subheadline)
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Undo this entry")
        }
        .padding(.vertical, 10)
    }
}

struct NoteRow: View {
    let note: FilamentNote
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(Format.dateTime(note.createdAt))
                if let spool = note.spool { Text("#\(spool.code)").monospaced() }
                Spacer()
                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash").frame(width: 28, height: 20).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete note")
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.mutedForeground)
            Text(note.body).font(.subheadline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.muted.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }
}

/// "Product page ↗" style link in the primary colour.
struct ExternalLink: View {
    let title: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            Label(title, systemImage: "arrow.up.right.square")
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(Theme.primary)
    }
}
