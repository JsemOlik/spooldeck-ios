import SwiftUI

struct SpoolFormView: View {
    enum Mode {
        case create(filamentId: Int?)
        case edit(SpoolDetail)
    }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    var onCreated: ((Int) -> Void)?

    @State private var filamentId: Int?
    @State private var initialWeight = ""
    @State private var remaining = ""
    @State private var quantity = 1
    @State private var spoolWeight = ""
    @State private var price = ""
    @State private var currency = ""
    @State private var vendor = ""
    @State private var hasPurchaseDate = false
    @State private var purchaseDate = Date()
    @State private var purchaseUrl = ""
    @State private var location = ""
    @State private var status: SpoolStatus?
    @State private var notes = ""

    @State private var options: [FilamentOption] = []
    @State private var vendors: [String] = []
    @State private var locations: [String] = []
    @State private var fieldErrors: [String: [String]] = [:]
    @State private var error: String?
    @State private var isSaving = false
    @State private var didPrefill = false

    private var isCreate: Bool {
        if case .create = mode { return true }
        return false
    }

    var body: some View {
        Form {
            Section {
                Picker("Filament", selection: $filamentId) {
                    Text("Choose…").tag(Int?.none)
                    ForEach(options) { option in
                        Text(option.label).tag(Int?.some(option.id))
                    }
                }
                .onChange(of: filamentId) { _, id in applyFilamentDefaults(id) }
                FieldErrorText(errors: fieldErrors, field: "filamentId")
            } footer: {
                if options.isEmpty { Text("Add a filament first, then add spools of it.") }
            }

            Section("Weight") {
                NumberField("Filament weight", text: $initialWeight, unit: "g", decimal: false)
                FieldErrorText(errors: fieldErrors, field: "initialWeight")
                if isCreate {
                    NumberField("Remaining now", text: $remaining, unit: "g")
                    FieldErrorText(errors: fieldErrors, field: "remaining")
                }
                NumberField("Empty spool", text: $spoolWeight, unit: "g", decimal: false)
                FieldErrorText(errors: fieldErrors, field: "spoolWeight")
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
                FieldErrorText(errors: fieldErrors, field: "currency")
                SuggestingTextField(title: "Shop", text: $vendor, suggestions: vendors)
                Toggle("Purchase date", isOn: $hasPurchaseDate.animation())
                if hasPurchaseDate {
                    DatePicker("Purchased", selection: $purchaseDate, displayedComponents: .date)
                }
                TextField("Product link", text: $purchaseUrl)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                FieldErrorText(errors: fieldErrors, field: "purchaseUrl")
            }

            Section("Storage") {
                SuggestingTextField(title: "Location", text: $location, suggestions: locations)
                Picker("Status", selection: $status) {
                    Text(isCreate ? "Automatic" : "Unchanged").tag(SpoolStatus?.none)
                    ForEach(SpoolStatus.allCases) { Text($0.label).tag(SpoolStatus?.some($0)) }
                }
                if isCreate {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...50)
                }
            }

            Section("Notes") {
                TextField("Anything worth remembering", text: $notes, axis: .vertical)
                    .lineLimit(2...8)
            }

            if let error {
                Section { Text(error).foregroundStyle(Theme.destructive) }
            }
        }
        .themedForm()
        .navigationTitle(isCreate ? "New spool" : "Edit spool")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isCreate ? "Add" : "Save") { Task { await save() } }
                    .disabled(filamentId == nil || initialWeight.isEmpty || isSaving)
            }
        }
        .task { await loadOptions() }
    }

    private func applyFilamentDefaults(_ id: Int?) {
        guard isCreate, let option = options.first(where: { $0.id == id }) else { return }
        initialWeight = Format.field(option.nominalWeight)
        if let weight = option.spoolWeight { spoolWeight = Format.field(weight) }
    }

    private func loadOptions() async {
        async let o: FilamentOptionsResponse? = try? app.api.get("filaments/options")
        async let v: ItemsResponse<Vendor>? = try? app.api.get("catalog/vendors")
        async let l: LocationsResponse? = try? app.api.get("locations")
        async let s: AppSettings? = try? app.api.get("settings")
        options = await o?.filaments ?? []
        vendors = await v?.items.map(\.name) ?? []
        locations = await l?.locations.map(\.name) ?? []
        let settings = await s
        guard !didPrefill else { return }
        didPrefill = true
        switch mode {
        case .create(let id):
            currency = settings?.currency ?? "EUR"
            filamentId = id
            applyFilamentDefaults(id)
        case .edit(let spool):
            filamentId = spool.filamentId
            initialWeight = Format.field(spool.initialWeight)
            spoolWeight = Format.field(spool.spoolWeight)
            price = Format.field(spool.price)
            currency = spool.currency ?? settings?.currency ?? ""
            vendor = spool.vendor?.name ?? ""
            if let date = DateParsing.localDay(spool.purchaseDate) {
                hasPurchaseDate = true
                purchaseDate = date
            }
            purchaseUrl = spool.purchaseUrl ?? ""
            location = spool.location ?? ""
            status = spool.status
            notes = spool.notes ?? ""
        }
    }

    private func save() async {
        guard let filamentId else { return }
        isSaving = true
        defer { isSaving = false }
        var body: FormBody = [
            "filamentId": String(filamentId),
            "initialWeight": initialWeight.decimalNormalized,
            "spoolWeight": spoolWeight.decimalNormalized,
            "price": price.decimalNormalized,
            "currency": currency,
            "vendor": vendor,
            "purchaseDate": hasPurchaseDate ? DateParsing.dayString(purchaseDate) : "",
            "purchaseUrl": purchaseUrl,
            "location": location,
            "status": status?.rawValue ?? "",
            "notes": notes,
        ]
        do {
            switch mode {
            case .create:
                body["remaining"] = remaining.decimalNormalized
                body["quantity"] = String(quantity)
                let result: MutationResult = try await app.api.post("spools", body: body)
                app.didMutate()
                dismiss()
                if let id = result.ids?.first, result.ids?.count == 1 { onCreated?(id) }
            case .edit(let spool):
                let _: MutationResult = try await app.api.put("spools/\(spool.id)", body: body)
                app.didMutate()
                dismiss()
            }
        } catch let apiError as APIError {
            fieldErrors = apiError.fieldErrors
            error = apiError.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }
    }
}
