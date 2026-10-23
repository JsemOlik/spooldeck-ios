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

struct ColorSwatch: View {
    let hex: String?
    var size: CGFloat = 36

    var body: some View {
        Circle()
            .fill(Color(hex: hex) ?? Color.secondary.opacity(0.2))
            .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 1))
            .overlay {
                if Color(hex: hex) == nil {
                    Image(systemName: "questionmark")
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct StatusBadge: View {
    let status: SpoolStatus

    var color: Color {
        switch status {
        case .sealed: .blue
        case .opened: .green
        case .empty: .orange
        case .archived: .gray
        }
    }

    var body: some View {
        Text(status.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

struct RemainingBar: View {
    let initial: Double
    let remaining: Double
    var lowStock: Double? = nil

    var body: some View {
        let percent = Weights.remainingPercent(initial: initial, remaining: remaining)
        let isLow = lowStock.map { remaining <= $0 } ?? false
        ProgressView(value: percent, total: 100)
            .tint(isLow ? .orange : .accentColor)
            .accessibilityLabel("\(Int(percent)) percent remaining")
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
            .font(.caption2)
            .foregroundStyle(.yellow)
            .accessibilityLabel("\(rating) of 5 stars")
        }
    }
}

/// A label/value row for detail screens. Hidden when the value is empty.
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
                .foregroundStyle(.red)
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
                .frame(maxWidth: 140)
                .accessibilityIdentifier(title)
            if let unit {
                Text(unit).foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Choose \(title.lowercased())")
            }
        }
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
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("Try again") { Task { await retry() } }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    var detail: String? = nil
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
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
