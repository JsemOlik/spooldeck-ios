import CoreImage
import SwiftUI
import UIKit

extension Color {
    /// Parses "#rrggbb".
    init?(hex: String?) {
        guard let hex else { return nil }
        let cleaned = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hexString: String? {
        guard let components = UIColor(self).cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components,
              components.count >= 3
        else { return nil }
        let r = Int((components[0] * 255).rounded()), g = Int((components[1] * 255).rounded()), b = Int((components[2] * 255).rounded())
        return String(format: "#%02x%02x%02x", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    }
}

/// A filament-coloured disc with a spool hub, as on the web.
struct ColorSwatch: View {
    let hex: String?
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle().fill(Color(hex: hex) ?? Theme.muted)
            Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 1)
            Circle()
                .fill(Theme.background.opacity(0.9))
                .overlay(Circle().strokeBorder(.primary.opacity(0.1), lineWidth: 1))
                .frame(width: size * 0.32, height: size * 0.32)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Status pill: Open is filled, Sealed is muted, the rest are outlined.
struct StatusBadge: View {
    let status: SpoolStatus

    var body: some View {
        Text(status == .opened ? "Open" : status.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .overlay {
                if !status.isActive { Capsule().strokeBorder(Theme.border) }
            }
    }

    private var foreground: Color {
        switch status {
        case .opened: Theme.primaryForeground
        case .sealed: .primary
        case .empty, .archived: Theme.mutedForeground
        }
    }

    private var background: Color {
        switch status {
        case .opened: Theme.primary
        case .sealed: Theme.muted
        case .empty, .archived: .clear
        }
    }
}

/// A small outlined tag ("Weigh-in", "Archived").
struct OutlineTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(Theme.mutedForeground)
            .overlay(Capsule().strokeBorder(Theme.border))
    }
}

struct RemainingBar: View {
    let initial: Double
    let remaining: Double
    var low = false
    var height: CGFloat = 6

    var body: some View {
        let percent = Weights.remainingPercent(initial: initial, remaining: remaining)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.muted)
                Capsule()
                    .fill(low ? Theme.destructive : Theme.primary)
                    .frame(width: proxy.size.width * percent / 100)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Remaining filament")
        .accessibilityValue("\(Int(percent)) percent")
    }
}

struct RatingView: View {
    let rating: Int?

    var body: some View {
        if let rating, rating > 0 {
            HStack(spacing: 1) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= rating ? "star.fill" : "star")
                }
            }
            .font(.caption)
            .foregroundStyle(Color.orange)
            .accessibilityElement()
            .accessibilityLabel("\(rating) of 5 stars")
        }
    }
}

/// Muted label on the left, value on the right; hidden when the value is empty (web: SpecList).
struct SpecRow<Value: View>: View {
    let label: String
    @ViewBuilder let value: Value

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label).foregroundStyle(Theme.mutedForeground)
            Spacer(minLength: 0)
            value
                .fontWeight(.medium)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

extension SpecRow where Value == Text {
    init(_ label: String, _ value: String) {
        self.label = label
        self.value = Text(value)
    }
}

struct SpecList: View {
    let items: [(String, String?)]

    var body: some View {
        let visible = items.compactMap { label, value -> (String, String)? in
            guard let value, !value.isEmpty, value != "—" else { return nil }
            return (label, value)
        }
        if visible.isEmpty {
            Text("Nothing recorded.").font(.subheadline).foregroundStyle(Theme.mutedForeground)
        } else {
            VStack(spacing: 10) {
                ForEach(visible, id: \.0) { label, value in
                    SpecRow(label, value)
                }
            }
        }
    }
}

/// A label/value row for grouped forms. Hidden when the value is empty.
struct InfoRow: View {
    let label: String
    let value: String?

    init(_ label: String, _ value: String?) {
        self.label = label
        self.value = value
    }

    var body: some View {
        if let value, !value.isEmpty, value != "—" {
            LabeledContent(label, value: value)
        }
    }
}

/// Shows server-side validation errors under a form field.
struct FieldErrorText: View {
    let errors: [String: [String]]
    let field: String

    var body: some View {
        if let messages = errors[field], !messages.isEmpty {
            Text(messages.joined(separator: " "))
                .font(.caption)
                .foregroundStyle(Theme.destructive)
        }
    }
}

/// A text field for numbers that keeps the raw string (the server parses it).
struct NumberField: View {
    let title: String
    @Binding var text: String
    var unit: String? = nil
    var decimal = true

    init(_ title: String, text: Binding<String>, unit: String? = nil, decimal: Bool = true) {
        self.title = title
        self._text = text
        self.unit = unit
        self.decimal = decimal
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, text: $text, prompt: Text("—"))
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 140)
                .accessibilityIdentifier(title)
            if let unit {
                Text(unit).foregroundStyle(Theme.mutedForeground)
            }
        }
    }
}

/// A text field with a menu of existing values to pick from (brand, material, shop, location…).
struct SuggestingTextField: View {
    let title: String
    @Binding var text: String
    let suggestions: [String]

    var body: some View {
        HStack {
            TextField(title, text: $text)
                .textInputAutocapitalization(.words)
            if !suggestions.isEmpty {
                Menu {
                    ForEach(suggestions, id: \.self) { s in
                        Button(s) { text = s }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundStyle(Theme.mutedForeground)
                }
                .accessibilityLabel("Choose \(title.lowercased())")
            }
        }
    }
}

/// The web's dashed empty state: an icon, a line of text and optional actions.
struct EmptyState<Actions: View>: View {
    let systemImage: String
    let title: String
    var message: String? = nil
    @ViewBuilder var actions: Actions

    init(systemImage: String, title: String, message: String? = nil, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.mutedForeground)
            Text(title).font(.headline)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.mutedForeground)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            HStack(spacing: 8) { actions }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, Theme.spacing)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
    }
}

/// Loading / error / content wrapper used by the screens that fetch from the API.
struct LoadingView<Value, Content: View>: View {
    let value: Value?
    let error: Error?
    let retry: () async -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        if let value {
            content(value)
        } else if let error {
            VStack {
                EmptyState(systemImage: "wifi.exclamationmark", title: "Couldn't load", message: error.localizedDescription) {
                    Button("Try again") { Task { await retry() } }
                        .buttonStyle(.spoolPrimary)
                }
            }
            .padding(Theme.spacing)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .screenBackground()
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .screenBackground()
        }
    }
}

/// Dashboard and filament stat tile: label, big value, detail line.
struct StatCard: View {
    let title: String
    let value: String
    var detail: String? = nil
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.mutedForeground)
                .lineLimit(1)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(1)
            }
        }
        .cardStyle(padding: 14)
    }
}

/// A web-style dropdown trigger for filter menus: "All materials ⌄".
struct FilterChip: View {
    let title: String
    var isActive = false

    var body: some View {
        HStack(spacing: 6) {
            Text(title).lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isActive ? Theme.primary : Theme.mutedForeground)
        }
        .font(.subheadline)
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(isActive ? Theme.primary.opacity(0.12) : Theme.card, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(isActive ? Theme.primary.opacity(0.5) : Theme.input)
        )
        .contentShape(Rectangle())
    }
}

/// "Pin + location" line used on cards and headers.
struct LocationLabel: View {
    let location: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "mappin").imageScale(.small)
            Text(location).lineLimit(1)
        }
    }
}

/// Generates a QR code image locally for a spool label URL.
enum QRCode {
    static func image(for string: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cg)
    }
}
