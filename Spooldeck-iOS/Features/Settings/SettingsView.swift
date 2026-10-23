import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var settings: AppSettings?
    @State private var me: Me?
    @State private var currency = ""
    @State private var lowStock = ""
    @State private var publicUrl = ""
    @State private var fieldErrors: [String: [String]] = [:]
    @State private var status: String?
    @State private var isSaving = false
    @State private var showPassword = false
    @State private var confirmSignOutEverywhere = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    LogoMark(size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spooldeck").font(.title3.weight(.semibold))
                        Text([me?.username ?? app.username, app.serverURL?.host()].compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                HStack {
                    Text("Currency")
                    Spacer()
                    TextField("EUR", text: $currency)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
                FieldErrorText(errors: fieldErrors, field: "currency")
                NumberField("Low stock below", text: $lowStock, unit: "g", decimal: false)
                FieldErrorText(errors: fieldErrors, field: "lowStockGrams")
                TextField(settings?.detectedUrl ?? "https://spools.example.com", text: $publicUrl)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                FieldErrorText(errors: fieldErrors, field: "publicUrl")
                Button {
                    Task { await saveSettings() }
                } label: {
                    if isSaving { ProgressView() } else { Text("Save") }
                }
                .disabled(settings == nil || isSaving)
            } header: {
                Text("General")
            } footer: {
                Text(status ?? "The public URL is printed into label QR codes. Leave it empty to use the address the server detects.")
            }

            Section("Catalog") {
                NavigationLink { CatalogListView(kind: .materials) } label: { Label("Materials", systemImage: "cube") }
                NavigationLink { CatalogListView(kind: .brands) } label: { Label("Brands", systemImage: "tag") }
                NavigationLink { CatalogListView(kind: .vendors) } label: { Label("Shops", systemImage: "cart") }
                NavigationLink { LocationsView() } label: { Label("Locations", systemImage: "mappin.and.ellipse") }
            }

            Section {
                LabeledContent("Signed in as", value: me?.username ?? app.username ?? "—")
                Button("Change password", systemImage: "key") { showPassword = true }
                Button("Sign out everywhere", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    confirmSignOutEverywhere = true
                }
                Button("Sign out", systemImage: "rectangle.portrait.and.arrow.forward", role: .destructive) {
                    Task { await app.signOut() }
                }
            } header: {
                Text("Account")
            } footer: {
                if let count = me?.sessionCount {
                    Text("\(count) active session\(count == 1 ? "" : "s"), including this app.")
                }
            }

            Section("Server") {
                if let url = app.serverURL {
                    Link(destination: url) {
                        LabeledContent("Address", value: url.host() ?? url.absoluteString)
                    }
                }
                Button("Use a different server", role: .destructive) { app.changeServer() }
            }

            Section {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                Link("Spooldeck on GitHub", destination: URL(string: "https://github.com/jsemolik/spooldeck")!)
            } header: {
                Text("About")
            } footer: {
                Text("Backups and restores, and the label designer's advanced options, are available in the web app.")
            }
        }
        .themedForm()
        .navigationTitle("Settings")
        .task(id: app.dataVersion) { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showPassword) {
            NavigationStack { ChangePasswordView() }
        }
        .confirmationDialog("Sign out everywhere?", isPresented: $confirmSignOutEverywhere, titleVisibility: .visible) {
            Button("Sign out all devices", role: .destructive) { Task { await app.signOut(everywhere: true) } }
        } message: {
            Text("Every browser and device signed in to Spooldeck, including this one, will need to sign in again.")
        }
    }

    private func load() async {
        async let s: AppSettings? = try? app.api.get("settings")
        async let m: Me? = try? app.api.get("me")
        if let loaded = await s {
            settings = loaded
            currency = loaded.currency
            lowStock = String(loaded.lowStockGrams)
            publicUrl = loaded.publicUrl
        }
        me = await m
    }

    private func saveSettings() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let result: MutationResult = try await app.api.put("settings", body: [
                "currency": currency,
                "lowStockGrams": lowStock,
                "publicUrl": publicUrl,
            ])
            fieldErrors = [:]
            status = result.message ?? "Saved"
            app.didMutate()
        } catch let apiError as APIError {
            fieldErrors = apiError.fieldErrors
            status = apiError.localizedDescription
        } catch {
            status = error.localizedDescription
        }
    }
}

struct ChangePasswordView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var fieldErrors: [String: [String]] = [:]
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                SecureField("Current password", text: $current).textContentType(.password)
                FieldErrorText(errors: fieldErrors, field: "current")
            }
            Section {
                SecureField("New password", text: $password).textContentType(.newPassword)
                FieldErrorText(errors: fieldErrors, field: "password")
                SecureField("Repeat new password", text: $confirm).textContentType(.newPassword)
                FieldErrorText(errors: fieldErrors, field: "confirm")
            } footer: {
                Text(error ?? "At least 10 characters. Other devices will be signed out.")
                    .foregroundStyle(error == nil ? Color.secondary : Theme.destructive)
            }
        }
        .themedForm()
        .navigationTitle("Change password")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(current.isEmpty || password.isEmpty || isSaving)
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let result: MutationResult = try await app.api.post("auth/password", body: [
                "current": current, "password": password, "confirm": confirm,
            ])
            if let token = result.token { app.store(token: token) }
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
