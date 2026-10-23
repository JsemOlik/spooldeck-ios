import Charts
import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var app
    @State private var dashboard: Dashboard?
    @State private var error: Error?

    var body: some View {
        LoadingView(value: dashboard, error: error, retry: load) { d in
            if d.spoolCount == 0 && d.recent.isEmpty {
                ContentUnavailableView {
                    Label("No spools yet", systemImage: "circle.circle")
                } description: {
                    Text("Scan a Prusament spool or add a filament to get started.")
                }
            } else {
                content(d)
            }
        }
        .navigationTitle("Dashboard")
        .task(id: app.dataVersion) { await load() }
        .refreshable { await load() }
    }

    private func content(_ d: Dashboard) -> some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatCard(title: "Spools in stock", value: "\(d.spoolCount)", systemImage: "circle.circle")
                    StatCard(title: "Filament on hand", value: Format.grams(d.remaining), systemImage: "scalemass")
                    StatCard(title: "Inventory value", value: Format.money(d.value, currency: d.currency), detail: "in \(d.currency)", systemImage: "banknote")
                    StatCard(title: "Last 30 days", value: Format.grams(d.used30), detail: d.prints30 == 1 ? "1 print" : "\(d.prints30) prints", systemImage: "printer")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if !d.low.isEmpty {
                Section {
                    ForEach(d.low.prefix(8)) { spool in
                        NavigationLink(value: Route.spool(id: spool.id)) {
                            SpoolRowView(spool: spool, lowStock: Double(d.lowStockGrams))
                        }
                    }
                    if d.low.count > 8 {
                        NavigationLink("All \(d.low.count) low spools", value: Route.spools(filter: SpoolFilter(lowOnly: true)))
                    }
                } header: {
                    Label("Running low", systemImage: "exclamationmark.triangle")
                } footer: {
                    Text("\(Format.grams(Double(d.lowStockGrams))) or less left.")
                }
            }

            if !d.recent.isEmpty {
                Section("Recent prints") {
                    ForEach(d.recent) { print in
                        NavigationLink(value: Route.spool(id: print.spoolId)) {
                            HStack(spacing: 12) {
                                ColorSwatch(hex: print.colorHex, size: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(print.printName ?? "Print")
                                        .lineLimit(1)
                                    Text([print.brandName, print.materialName, print.colorName ?? print.filamentName].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(Format.grams(print.grams)).monospacedDigit()
                                    Text(Format.relative(print.createdAt))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            if !d.byMaterial.isEmpty {
                Section("Usage by material, last 30 days") {
                    Chart(d.byMaterial) { item in
                        BarMark(x: .value("Grams", item.grams), y: .value("Material", item.material))
                            .annotation(position: .trailing) {
                                Text(Format.grams(item.grams))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: CGFloat(max(d.byMaterial.count, 1)) * 36)
                    .padding(.vertical, 8)
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
