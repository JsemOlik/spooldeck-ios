import SwiftUI

struct FilamentFormView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let filament: Filament?

    @State private var name = ""
    @State private var brand = ""
    @State private var material = ""
    @State private var colorName = ""
    @State private var colorHex = ""
    @State private var diameter = "1.75"
    @State private var nominalWeight = "1000"
    @State private var spoolWeight = ""
    @State private var nozzleMin = ""
    @State private var nozzleMax = ""
    @State private var bedMin = ""
    @State private var bedMax = ""
    @State private var dryingTemp = ""
    @State private var dryingHours = ""
    @State private var maxSpeed = ""
    @State private var fan = ""
    @State private var productUrl = ""
    @State private var imageUrl = ""
    @State private var rating = 0

    @State private var brands: [String] = []
    @State private var materials: [String] = []
    @State private var fieldErrors: [String: [String]] = [:]
    @State private var error: String?
    @State private var isSaving = false
    @State private var addSpoolAfter = false
    @State private var createdId: Int?

    var body: some View {
        Form {
            Section {
                TextField("Name, e.g. Prusament PLA Galaxy Black", text: $name)
                FieldErrorText(errors: fieldErrors, field: "name")
                SuggestingTextField(title: "Brand", text: $brand, suggestions: brands)
                SuggestingTextField(title: "Material", text: $material, suggestions: materials)
            } footer: {
                Text("New brands and materials are created automatically.")
            }

            Section("Color") {
                TextField("Color name", text: $colorName)
                HStack {
                    TextField("#ff8800", text: $colorHex)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    ColorPicker("Pick color", selection: Binding(
                        get: { Color(hex: colorHex) ?? .gray },
                        set: { colorHex = $0.hexString ?? colorHex }
                    ), supportsOpacity: false)
                    .labelsHidden()
                }
                FieldErrorText(errors: fieldErrors, field: "colorHex")
            }

            Section("Spool") {
                NumberField("Diameter", text: $diameter, unit: "mm")
                FieldErrorText(errors: fieldErrors, field: "diameter")
                NumberField("Net weight", text: $nominalWeight, unit: "g", decimal: false)
                FieldErrorText(errors: fieldErrors, field: "nominalWeight")
                NumberField("Empty spool", text: $spoolWeight, unit: "g", decimal: false)
                FieldErrorText(errors: fieldErrors, field: "spoolWeight")
            }

            Section {
                rangeRow("Nozzle", min: $nozzleMin, max: $nozzleMax, field: "nozzleMax")
                rangeRow("Bed", min: $bedMin, max: $bedMax, field: "bedMax")
                NumberField("Max speed", text: $maxSpeed, unit: "mm/s", decimal: false)
                TextField("Fan, e.g. 100%", text: $fan)
                NumberField("Drying temp", text: $dryingTemp, unit: "°C", decimal: false)
                NumberField("Drying time", text: $dryingHours, unit: "h")
            } header: {
                Text("Print settings")
            } footer: {
                Text("Leave temperatures empty to use the material's defaults.")
            }

            Section("More") {
                TextField("Product link", text: $productUrl)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                FieldErrorText(errors: fieldErrors, field: "productUrl")
                TextField("Image link", text: $imageUrl)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                FieldErrorText(errors: fieldErrors, field: "imageUrl")
                HStack {
                    Text("Rating")
                    Spacer()
                    ForEach(1...5, id: \.self) { i in
                        Image(systemName: i <= rating ? "star.fill" : "star")
                            .foregroundStyle(.yellow)
                            .onTapGesture { rating = rating == i ? 0 : i }
                    }
                }
            }

            if filament == nil {
                Section {
                    Toggle("Add a spool next", isOn: $addSpoolAfter)
                }
            }

            if let error {
                Section { Text(error).foregroundStyle(Theme.destructive) }
            }
        }
        .themedForm()
        .navigationTitle(filament == nil ? "New filament" : "Edit filament")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(filament == nil ? "Add" : "Save") { Task { await save() } }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
        .navigationDestination(item: $createdId) { id in
            SpoolFormView(mode: .create(filamentId: id))
        }
        .task { await load() }
    }

    private func rangeRow(_ title: String, min: Binding<String>, max: Binding<String>, field: String) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                TextField("min", text: min).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 56)
                Text("–")
                TextField("max", text: max).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 56)
                Text("°C").foregroundStyle(.secondary)
            }
            FieldErrorText(errors: fieldErrors, field: field)
        }
    }

    private func load() async {
        async let b: ItemsResponse<Brand>? = try? app.api.get("catalog/brands")
        async let m: ItemsResponse<Material>? = try? app.api.get("catalog/materials")
        brands = await b?.items.map(\.name) ?? []
        materials = await m?.items.map(\.name) ?? []

        guard let f = filament, name.isEmpty else { return }
        name = f.name
        brand = f.brand?.name ?? ""
        material = f.material?.name ?? ""
        colorName = f.colorName ?? ""
        colorHex = f.colorHex ?? ""
        diameter = Format.field(f.diameter)
        nominalWeight = Format.field(f.nominalWeight)
        spoolWeight = Format.field(f.spoolWeight)
        nozzleMin = Format.field(f.nozzleMin)
        nozzleMax = Format.field(f.nozzleMax)
        bedMin = Format.field(f.bedMin)
        bedMax = Format.field(f.bedMax)
        dryingTemp = Format.field(f.dryingTemp)
        dryingHours = Format.field(f.dryingHours)
        maxSpeed = Format.field(f.maxSpeed)
        fan = f.fan ?? ""
        productUrl = f.productUrl ?? ""
        imageUrl = f.imageUrl ?? ""
        rating = f.rating ?? 0
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let body: FormBody = [
            "name": name,
            "brand": brand,
            "material": material,
            "colorName": colorName,
            "colorHex": colorHex,
            "diameter": diameter.decimalNormalized,
            "nominalWeight": nominalWeight.decimalNormalized,
            "spoolWeight": spoolWeight.decimalNormalized,
            "nozzleMin": nozzleMin,
            "nozzleMax": nozzleMax,
            "bedMin": bedMin,
            "bedMax": bedMax,
            "dryingTemp": dryingTemp,
            "dryingHours": dryingHours.decimalNormalized,
            "maxSpeed": maxSpeed,
            "fan": fan,
            "productUrl": productUrl,
            "imageUrl": imageUrl,
            "rating": rating > 0 ? String(rating) : "",
        ]
        do {
            if let filament {
                let _: MutationResult = try await app.api.put("filaments/\(filament.id)", body: body)
                app.didMutate()
                dismiss()
            } else {
                let result: MutationResult = try await app.api.post("filaments", body: body)
                app.didMutate()
                if addSpoolAfter, let id = result.id {
                    createdId = id
                } else {
                    dismiss()
                }
            }
        } catch let apiError as APIError {
            fieldErrors = apiError.fieldErrors
            error = apiError.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }
    }
}
