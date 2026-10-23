import SwiftUI

struct PrusamentImportView: View {
    @Environment(AppModel.self) private var app
    let url: String

    @State private var preview: PrusamentPreview?
    @State private var error: Error?
    @State private var importedId: Int?

    @State private var price = ""
    @State private var currency = ""
    @State private var vendor = ""
    @State private var hasPurchaseDate = false
    @State private var purchaseDate = Date()
    @State private var location = ""
    @State private var remaining = ""
    @State private var notes = ""
    @State private var vendors: [String] = []
    @State private var locations: [String] = []
    @State private var fieldErrors: [String: [String]] = [:]
    @State private var importError: String?
    @State private var isImporting = false

    var body: some View {
        LoadingView(value: preview, error: error, retry: load) { preview in
            if let existing = preview.existingSpoolId {
                ContentUnavailableView {
                    Label("Already in Spooldeck", systemImage: "checkmark.circle")
                } description: {
                    Text("This spool was imported before.")
                } actions: {
                    NavigationLink("Open spool", value: Route.spool(id: existing))
                        .buttonStyle(.borderedProminent)
                }
            } else if let f = preview.filament, let s = preview.spool {
                form(preview, filament: f, spool: s)
            }
        }
        .navigationTitle("Import Prusament")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $importedId) { id in
            SpoolDetailView(spoolId: id)
        }
        .task { await load() }
    }

    @ViewBuilder
    private func form(_ preview: PrusamentPreview, filament f: PrusamentPreview.FilamentInfo, spool s: PrusamentPreview.SpoolInfo) -> some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    if let image = f.imageUrl, let imageURL = URL(string: image) {
                        AsyncImage(url: imageURL) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() } else { ColorSwatch(hex: f.colorHex, size: 64) }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        ColorSwatch(hex: f.colorHex, size: 64)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text([f.brand, f.material].compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(f.colorName ?? f.name).font(.title3.bold())
                    }
                }
                if let existing = preview.existingFilament {
                    Label("Adds a spool to “\(existing.name)”", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else {
                    Label("Creates a new filament", systemImage: "plus.circle")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Data pulled from prusament.com. Add what Prusa doesn't know: price, shop and where you keep it.")
            }

            Section("From prusament.com") {
                LabeledContent("Net weight", value: Format.grams(s.initialWeight))
                InfoRow("Empty spool", s.spoolWeight.map { Format.grams($0) })
                InfoRow("Length", s.lengthM.map { Format.length($0) })
                LabeledContent("Nozzle", value: Format.range(f.nozzleMin, f.nozzleMax))
                LabeledContent("Bed", value: Format.range(f.bedMin, f.bedMax))
                InfoRow("Manufactured", s.manufactureDate.map { Format.day($0) })
                InfoRow("Diameter tolerance", s.diameterTolerance.map { "± \(Format.field($0 / 1000)) mm" })
                InfoRow("List price", preview.price.map { Format.money($0.amount, currency: $0.currency) })
            }

            Section("Purchase") {
                HStack {
                    NumberField("Price", text: $price)
                    TextField("EUR", text: $currency)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .frame(width: 56)
                }
                FieldErrorText(errors: fieldErrors, field: "price")
                SuggestingTextField(title: "Shop", text: $vendor, suggestions: vendors)
                Toggle("Purchase date", isOn: $hasPurchaseDate.animation())
                if hasPurchaseDate {
                    DatePicker("Purchased", selection: $purchaseDate, displayedComponents: .date)
                }
            }

            Section {
                SuggestingTextField(title: "Location", text: $location, suggestions: locations)
                NumberField("Remaining now", text: $remaining, unit: "g")
                FieldErrorText(errors: fieldErrors, field: "remaining")
                TextField("Notes", text: $notes, axis: .vertical)
            } footer: {
                Text("Leave “Remaining now” empty for a sealed spool.")
            }

            if let importError {
                Section { Text(importError).foregroundStyle(.red) }
            }

            Section {
                Button {
                    Task { await runImport() }
                } label: {
                    HStack {
                        Spacer()
                        if isImporting { ProgressView() } else { Text("Import spool").bold() }
                        Spacer()
                    }
                }
                .disabled(isImporting)
            }
        }
    }

    private func load() async {
        do {
            let result: PrusamentPreview = try await app.api.get("prusament/preview", query: ["url": url])
            if let listPrice = result.price, price.isEmpty {
                price = Format.field(listPrice.amount)
                currency = listPrice.currency
            }
            preview = result
            error = nil
        } catch {
            self.error = error
        }
        async let v: ItemsResponse<Vendor>? = try? app.api.get("catalog/vendors")
        async let l: LocationsResponse? = try? app.api.get("locations")
        async let s: AppSettings? = try? app.api.get("settings")
        vendors = await v?.items.map(\.name) ?? []
        locations = await l?.locations.map(\.name) ?? []
        if currency.isEmpty { currency = await s?.currency ?? "EUR" }
    }

    private func runImport() async {
        isImporting = true
        defer { isImporting = false }
        do {
            let result: MutationResult = try await app.api.post("prusament/import", body: [
                "url": url,
                "price": price.decimalNormalized,
                "currency": currency,
                "vendor": vendor,
                "purchaseDate": hasPurchaseDate ? DateParsing.dayString(purchaseDate) : "",
                "location": location,
                "remaining": remaining.decimalNormalized,
                "notes": notes,
            ])
            app.didMutate()
            importedId = result.id
        } catch let apiError as APIError {
            fieldErrors = apiError.fieldErrors
            importError = apiError.localizedDescription
        } catch {
            importError = error.localizedDescription
        }
    }
}
