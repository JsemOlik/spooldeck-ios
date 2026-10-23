import SwiftUI
import WebKit

/// The web app's label designer in a web view. The API token is also a valid web session,
/// so it's handed over as the session cookie and the designer opens already signed in.
struct LabelsWebView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let spoolIds: [Int]

    @State private var webView: WKWebView?
    @State private var isLoading = true

    private var startURL: URL? {
        guard let base = app.serverURL else { return nil }
        var components = URLComponents(url: base.appending(path: "labels"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "spools", value: spoolIds.map(String.init).joined(separator: ","))]
        return components?.url
    }

    var body: some View {
        NavigationStack {
            Group {
                if let startURL, let token = app.token {
                    WebView(url: startURL, token: token, webView: $webView, isLoading: $isLoading)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView("Not signed in", systemImage: "person.crop.circle.badge.xmark")
                }
            }
            .overlay {
                if isLoading { ProgressView() }
            }
            .navigationTitle("Labels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Back", systemImage: "chevron.backward") { webView?.goBack() }
                        .disabled(!(webView?.canGoBack ?? false))
                    Button("Print", systemImage: "printer") { printPage() }
                }
            }
        }
    }

    private func printPage() {
        guard let webView else { return }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = "Spooldeck labels"
        controller.printInfo = info
        controller.printFormatter = webView.viewPrintFormatter()
        controller.present(animated: true)
    }
}

private struct WebView: UIViewRepresentable {
    let url: URL
    let token: String
    @Binding var webView: WKWebView?
    @Binding var isLoading: Bool

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true

        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: "spooldeck_session",
            .value: token,
            .domain: url.host() ?? "",
            .path: "/",
            .expires: Date().addingTimeInterval(30 * 24 * 60 * 60),
        ]
        if url.scheme == "https" { properties[.secure] = "TRUE" }
        let request = URLRequest(url: url)
        if let cookie = HTTPCookie(properties: properties) {
            configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
                view.load(request)
            }
        } else {
            view.load(request)
        }
        DispatchQueue.main.async { webView = view }
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: WebView
        init(_ parent: WebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        /// The designer opens its print page in a new tab; keep it in this view instead.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }
    }
}
