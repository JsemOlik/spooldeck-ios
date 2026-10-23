import Foundation

/// Display helpers, ported from the web app's src/lib/format.ts and src/lib/weights.ts.
enum Format {
    static func grams(_ g: Double?, precise: Bool = false) -> String {
        guard let g, !g.isNaN else { return "—" }
        if abs(g) >= 1000 && !precise {
            let kg = (g / 1000).formatted(.number.precision(.fractionLength(0...2)))
            return "\(kg) kg"
        }
        return "\(g.formatted(.number.precision(.fractionLength(0...1)))) g"
    }

    static func money(_ amount: Double?, currency: String) -> String {
        guard let amount, !amount.isNaN else { return "—" }
        return amount.formatted(.currency(code: currency).precision(.fractionLength(2)))
    }

    static func range(_ min: Int?, _ max: Int?, unit: String = "°C") -> String {
        switch (min, max) {
        case (nil, nil): "—"
        case let (min?, max?): min == max ? "\(min)\(unit)" : "\(min)–\(max)\(unit)"
        case let (value?, nil), let (nil, value?): "\(value)\(unit)"
        }
    }

    static func length(_ m: Double?) -> String {
        guard let m, !m.isNaN else { return "—" }
        return "\(Int(m.rounded())) m"
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static func dateTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Formats a stored `YYYY-MM-DD` string for display.
    static func day(_ string: String?) -> String {
        guard let string, !string.isEmpty else { return "—" }
        return DateParsing.localDay(string).map { date($0) } ?? string
    }

    static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }

    /// Number for a form field, without grouping separators.
    static func field(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.grouping(.never).precision(.fractionLength(0...3)))
    }

    static func field(_ value: Int?) -> String {
        value.map(String.init) ?? ""
    }
}

enum Weights {
    /// Estimated filament length in metres for a given mass.
    static func estimateLengthM(grams: Double, diameterMm: Double = 1.75, density: Double = 1.24) -> Double {
        guard grams > 0, diameterMm > 0, density > 0 else { return 0 }
        let volumeCm3 = grams / density
        let radiusCm = diameterMm / 20
        let lengthCm = volumeCm3 / (Double.pi * radiusCm * radiusCm)
        return lengthCm / 100
    }

    static func remainingPercent(initial: Double, remaining: Double) -> Double {
        guard initial > 0 else { return 0 }
        return min(100, max(0, remaining / initial * 100))
    }

    static func pricePerGram(price: Double?, initialWeight: Double) -> Double? {
        guard let price, initialWeight > 0 else { return nil }
        return price / initialWeight
    }

    static func cost(grams: Double, price: Double?, initialWeight: Double) -> Double? {
        pricePerGram(price: price, initialWeight: initialWeight).map { $0 * grams }
    }
}

extension String {
    /// Normalises a localised decimal ("12,5") into the form the server parses ("12.5").
    var decimalNormalized: String {
        replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")
    }
}
