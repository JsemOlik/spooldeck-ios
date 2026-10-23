import SwiftUI

struct LogUsageSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let spool: SpoolDetail

    @State private var grams = ""
    @State private var printName = ""
    @State private var note = ""
    @State private var isSaving = false
    @State private var fieldErrors: [String: [String]] = [:]
    @State private var error: String?
    @FocusState private var gramsFocused: Bool

    var body: some View {
        Form {
            Section {
                NumberField("Grams used", text: $grams, unit: "g")
                    .focused($gramsFocused)
                FieldErrorText(errors: fieldErrors, field: "grams")
                if let g = Double(grams.decimalNormalized), g > 0 {
                    LabeledContent("Left after", value: Format.grams(spool.remaining - g))
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("\(Format.grams(spool.remaining)) left on #\(spool.code). Your slicer shows the grams for each print.")
            }
            Section {
                TextField("Print name (optional)", text: $printName)
                TextField("Note (optional)", text: $note, axis: .vertical)
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Log usage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Log") { Task { await save() } }
                    .disabled(grams.isEmpty || isSaving)
            }
        }
        .onAppear { gramsFocused = true }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let _: MutationResult = try await app.api.post("spools/\(spool.id)/usage", body: [
                "grams": grams.decimalNormalized,
                "printName": printName,
                "note": note,
            ])
            app.didMutate()
            dismiss()
        } catch let apiError as APIError {
            fieldErrors = apiError.fieldErrors
            error = apiError.fieldErrors.isEmpty ? apiError.localizedDescription : nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct WeighInSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let spool: SpoolDetail

    @State private var scaleGrams = ""
    @State private var includesSpool: Bool
    @State private var note = ""
    @State private var isSaving = false
    @State private var fieldErrors: [String: [String]] = [:]
    @State private var error: String?
    @FocusState private var focused: Bool

    init(spool: SpoolDetail) {
        self.spool = spool
        _includesSpool = State(initialValue: spool.spoolWeight != nil)
    }

    /// Mirrors weighInUsage() in the web app's src/lib/weights.ts.
    private var delta: Double? {
        guard let scale = Double(scaleGrams.decimalNormalized) else { return nil }
        let net = includesSpool ? scale - (spool.spoolWeight ?? 0) : scale
        return ((spool.remaining - max(0, net)) * 10).rounded() / 10
    }

    var body: some View {
        Form {
            Section {
                NumberField("Scale reading", text: $scaleGrams, unit: "g")
                    .focused($focused)
                FieldErrorText(errors: fieldErrors, field: "scaleGrams")
                Toggle("Includes the empty spool", isOn: $includesSpool)
                    .disabled(spool.spoolWeight == nil)
            } footer: {
                if let weight = spool.spoolWeight {
                    Text("Empty spool weighs \(Format.grams(weight)). Currently \(Format.grams(spool.remaining)) of filament on record.")
                } else {
                    Text("Set the empty spool weight on this spool to weigh it with the spool on. For now, enter the filament weight only.")
                }
            }
            if let delta {
                Section {
                    if delta > 0 {
                        LabeledContent("Will record", value: "\(Format.grams(delta)) used")
                    } else if delta < 0 {
                        LabeledContent("Will add back", value: Format.grams(-delta))
                    } else {
                        Text("Matches what's on record.").foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                TextField("Note (optional)", text: $note, axis: .vertical)
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Weigh in")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(scaleGrams.isEmpty || isSaving)
            }
        }
        .onAppear { focused = true }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let _: MutationResult = try await app.api.post("spools/\(spool.id)/weigh-in", body: [
                "scaleGrams": scaleGrams.decimalNormalized,
                "includesSpool": includesSpool ? "true" : "false",
                "note": note,
            ])
            app.didMutate()
            dismiss()
        } catch let apiError as APIError {
            fieldErrors = apiError.fieldErrors
            error = apiError.fieldErrors.isEmpty ? apiError.localizedDescription : nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct NoteComposer: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let filamentId: Int
    var spoolId: Int?

    @State private var text = ""
    @State private var error: String?
    @State private var isSaving = false
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            Section {
                TextField("What did you learn about this filament?", text: $text, axis: .vertical)
                    .lineLimit(4...12)
                    .focused($focused)
            } footer: {
                if let error { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("New note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
        .onAppear { focused = true }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            var body: FormBody = ["body": text]
            if let spoolId { body["spoolId"] = String(spoolId) }
            let _: MutationResult = try await app.api.post("filaments/\(filamentId)/notes", body: body)
            app.didMutate()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
