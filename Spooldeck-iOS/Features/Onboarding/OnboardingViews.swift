import SwiftUI

struct ServerView: View {
    @Environment(AppModel.self) private var app
    @State private var address = UserDefaults.standard.string(forKey: "lastServerInput") ?? ""
    @State private var isConnecting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "circle.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.tint)
                        Text("Spooldeck")
                            .font(.largeTitle.bold())
                        Text("Connect to your self-hosted Spooldeck to track filament from your phone.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("spools.example.com", text: $address)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit { Task { await connect() } }
                } header: {
                    Text("Server address")
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text("The address you open Spooldeck at in your browser. https:// is assumed unless you type http://.")
                    }
                }

                Section {
                    Button {
                        Task { await connect() }
                    } label: {
                        HStack {
                            Spacer()
                            if isConnecting { ProgressView() } else { Text("Continue").bold() }
                            Spacer()
                        }
                    }
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || isConnecting)
                }
            }
        }
    }

    private func connect() async {
        isConnecting = true
        error = nil
        defer { isConnecting = false }
        UserDefaults.standard.set(address, forKey: "lastServerInput")
        do {
            try await app.connect(to: address)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct LoginView: View {
    @Environment(AppModel.self) private var app
    @State private var username = UserDefaults.standard.string(forKey: "lastUsername") ?? ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var error: String?
    @FocusState private var focus: Field?

    enum Field { case username, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await signIn() } }
                } header: {
                    Text(app.serverURL?.host() ?? "")
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                }

                Section {
                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSigningIn { ProgressView() } else { Text("Sign in").bold() }
                            Spacer()
                        }
                    }
                    .disabled(username.isEmpty || password.isEmpty || isSigningIn)
                }

                Section {
                    Button("Use a different server", role: .destructive) { app.changeServer() }
                }
            }
            .navigationTitle("Sign in")
            .onAppear { focus = username.isEmpty ? .username : .password }
        }
    }

    private func signIn() async {
        isSigningIn = true
        error = nil
        defer { isSigningIn = false }
        UserDefaults.standard.set(username, forKey: "lastUsername")
        do {
            try await app.signIn(username: username, password: password)
            password = ""
        } catch {
            self.error = error.localizedDescription
        }
    }
}
