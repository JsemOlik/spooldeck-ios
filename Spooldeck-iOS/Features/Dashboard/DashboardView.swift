import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var app
    @State private var dashboard: Dashboard?
    @State private var error: Error?
    @State private var showNewSpool = false
    @State private var showNewFilament = false

    var body: some View {
        LoadingView(value: dashboard, error: error, retry: load) { d in
            Screen {
                stats(d)
                if d.spoolCount == 0 && d.recent.isEmpty {
                    EmptyState(
                        systemImage: "shippingbox",
                        title: "Your shelf is empty",
                        message: "Scan the QR code on a Prusament spool to import it automatically, or add any other filament by hand and print a label for it."
                    ) {
                        Button("Add filament") { showNewFilament = true }
                            .buttonStyle(.spoolOutline)
                    }
                } else {
                    runningLow(d)
                    recentPrints(d)
                    if !d.byMaterial.isEmpty { usageByMaterial(d) }
                }
            }
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add spool", systemImage: "plus") { showNewSpool = true }
            }
        }
        .sheet(isPresented: $showNewSpool) {
            NavigationStack { SpoolFormView(mode: .create(filamentId: nil)) }
        }
        .sheet(isPresented: $showNewFilament) {
            NavigationStack { FilamentFormView(filament: nil) }
        }
        .task(id: app.dataVersion) { await load() }
        .refreshable { await load() }
    }

    private func stats(_ d: Dashboard) -> some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatCard(title: "Spools in stock", value: "\(d.spoolCount)", detail: "\(d.low.count) running low")
                StatCard(title: "Filament on hand", value: Format.grams(d.remaining), detail: "across all spools")
            }
            GridRow {
                StatCard(title: "Inventory value", value: Format.money(d.value, currency: d.currency), detail: "remaining filament")
                StatCard(title: "Last 30 days", value: Format.grams(d.used30), detail: d.prints30 == 1 ? "1 print logged" : "\(d.prints30) prints logged")
            }
        }
    }

    private func runningLow(_ d: Dashboard) -> some View {
        Card("Running low", systemImage: "exclamationmark.triangle", iconColor: Theme.destructive) {
            Text("≤ \(Format.grams(Double(d.lowStockGrams)))")
                .font(.caption)
                .foregroundStyle(Theme.mutedForeground)
        } content: {
            if d.low.isEmpty {
                Text("Nothing is running low.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.mutedForeground)
            } else {
                VStack(spacing: 14) {
                    ForEach(d.low.prefix(8)) { spool in
                        NavigationLink(value: Route.spool(id: spool.id)) {
                            HStack(spacing: 12) {
                                ColorSwatch(hex: spool.colorHex, size: 28)
                                VStack(spacing: 6) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text("\(Text(spool.title).fontWeight(.medium))\(Text(spool.materialName.map { " · \($0)" } ?? "").foregroundStyle(Theme.mutedForeground))")
                                            .lineLimit(1)
                                        Spacer()
                                        Text(Format.grams(max(0, spool.remaining)))
                                            .fontWeight(.semibold)
                                            .monospacedDigit()
                                            .foregroundStyle(Theme.destructive)
                                    }
                                    .font(.subheadline)
                                    RemainingBar(initial: spool.initialWeight, remaining: spool.remaining, low: true)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if d.low.count > 8 {
                        NavigationLink(value: Route.spools(filter: SpoolFilter(lowOnly: true))) {
                            Text("All \(d.low.count) low spools →").font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func recentPrints(_ d: Dashboard) -> some View {
        Card("Recent prints") {
            if d.recent.isEmpty {
                Text("No prints logged yet. Open a spool and tap “Log usage”.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.mutedForeground)
            } else {
                DividedRows(data: d.recent) { print in
                    NavigationLink(value: Route.spool(id: print.spoolId)) {
                        HStack(spacing: 12) {
                            ColorSwatch(hex: print.colorHex, size: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(print.printName ?? "Print")
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text("\(print.colorName ?? print.filamentName) · \(Format.relative(print.createdAt))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.mutedForeground)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(Format.grams(print.grams, precise: true))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func usageByMaterial(_ d: Dashboard) -> some View {
        let maxGrams = max(1, d.byMaterial.map(\.grams).max() ?? 1)
        return Card("Usage by material · last 30 days") {
            VStack(spacing: 10) {
                ForEach(d.byMaterial) { item in
                    HStack(spacing: 12) {
                        Text(item.material)
                            .fontWeight(.medium)
                            .frame(width: 64, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.muted)
                                Capsule().fill(Theme.primary).frame(width: proxy.size.width * item.grams / maxGrams)
                            }
                        }
                        .frame(height: 8)
                        Text(Format.grams(item.grams))
                            .monospacedDigit()
                            .frame(width: 72, alignment: .trailing)
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private func load() async {
        do {
            dashboard = try await app.api.get("dashboard")
            error = nil
        } catch {
            if dashboard == nil { self.error = error }
        }
    }
}
