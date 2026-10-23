import SwiftUI

struct ServerView: View {
    @Environment(AppModel.self) private var app
    @State private var address = UserDefaults.standard.string(forKey: "lastServerInput") ?? ""
    @State private var isConnecting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            OnboardingScreen(subtitle: "Connect to your self-hosted Spooldeck to track filament from your phone.") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Server address").font(.subheadline.weight(.medium))
                    TextField("spools.example.com", text: $address)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit { Task { await connect() } }
                        .modifier(InputStyle())
                    Text(error ?? "The address you open Spooldeck at in your browser. https:// is assumed unless you type http://.")
                        .font(.caption)
                        .foregroundStyle(error == nil ? Theme.mutedForeground : Theme.destructive)
                }
                Button {
                    Task { await connect() }
                } label: {
                    if isConnecting { ProgressView().tint(Theme.primaryForeground) } else { Text("Continue") }
                }
                .buttonStyle(.spool(.primary, fullWidth: true))
                .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || isConnecting)
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
            OnboardingScreen(subtitle: "Sign in to \(app.serverURL?.host() ?? "your server").") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Username").font(.subheadline.weight(.medium))
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                        .modifier(InputStyle())
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password").font(.subheadline.weight(.medium))
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await signIn() } }
                        .modifier(InputStyle())
                    if let error {
                        Text(error).font(.caption).foregroundStyle(Theme.destructive)
                    }
                }
                Button {
                    Task { await signIn() }
                } label: {
                    if isSigningIn { ProgressView().tint(Theme.primaryForeground) } else { Text("Sign in") }
                }
                .buttonStyle(.spool(.primary, fullWidth: true))
                .disabled(username.isEmpty || password.isEmpty || isSigningIn)
            } footer: {
                Button("Use a different server") { app.changeServer() }
                    .buttonStyle(.spool(.ghost, compact: true))
                    .foregroundStyle(Theme.mutedForeground)
            }
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

/// Centered logo, a short line and a card with the form, like the web login page.
private struct OnboardingScreen<Content: View, Footer: View>: View {
    let subtitle: String
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    init(subtitle: String, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer = { EmptyView() }) {
        self.subtitle = subtitle
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    LogoMark(size: 56)
                    Text("Spooldeck").font(.largeTitle.weight(.semibold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.mutedForeground)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 48)
                VStack(alignment: .leading, spacing: 16) { content }
                    .cardStyle(padding: 20)
                footer
            }
            .padding(.horizontal, Theme.spacing)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
    }
}

/// A bordered text input like the web's <Input>.
struct InputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.input))
    }
}
