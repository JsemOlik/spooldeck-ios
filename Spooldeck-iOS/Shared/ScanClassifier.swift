import Foundation

/// Port of the web app's src/lib/scan.ts: classifies scanned or pasted text as a Prusament
/// spool URL, a Spooldeck label URL (…/s/CODE) or a bare spool code.
enum ScanTarget: Equatable {
    case prusament(url: String)
    case code(String)
    case unknown(String)
}

enum ScanClassifier {
    static let codeAlphabet = Set("23456789ABCDEFGHJKMNPQRSTUVWXYZ")
    static let codeLength = 6

    static func isSpoolCode(_ code: String) -> Bool {
        code.count == codeLength && code.allSatisfy { codeAlphabet.contains($0) }
    }

    static func isPrusamentURL(_ text: String) -> Bool {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host()?.lowercased(), host == "prusament.com" || host == "www.prusament.com"
        else { return false }
        return url.path().range(of: #"^/(?:[a-z]{2}(?:-[a-z]{2})?/)?spool/(?:\d+/)?[0-9a-f]{6,32}/?$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func classify(_ text: String) -> ScanTarget {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isPrusamentURL(trimmed) { return .prusament(url: trimmed) }

        if let url = URL(string: trimmed), url.scheme != nil,
           let match = url.path().firstMatch(of: #/\/s\/([A-Za-z0-9]+)\/?$/#) {
            let code = String(match.1).uppercased()
            if isSpoolCode(code) { return .code(code) }
        }

        let bare = (trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed).uppercased()
        if isSpoolCode(bare) { return .code(bare) }
        return .unknown(trimmed)
    }
}
