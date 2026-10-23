import Foundation

// Codable mirrors of the Spooldeck /api/v1 responses (Drizzle rows serialised as JSON).

nonisolated enum SpoolStatus: String, Codable, CaseIterable, Identifiable {
    case sealed, opened, empty, archived
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var isActive: Bool { self == .sealed || self == .opened }
}

nonisolated enum UsageKind: String, Codable {
    case print, adjustment
    case weighIn = "weigh_in"

    var label: String {
        switch self {
        case .print: "Print"
        case .adjustment: "Adjustment"
        case .weighIn: "Weigh-in"
        }
    }
}

nonisolated struct User: Codable, Hashable {
    let id: Int
    let username: String
}

nonisolated struct Me: Codable {
    let id: Int
    let username: String
    let sessionCount: Int
}

nonisolated struct LoginResponse: Codable {
    let token: String
    let expiresAt: Date
    let user: User
}

/// The generic `{ ok, id?, ids?, message? }` result of a mutation.
nonisolated struct MutationResult: Codable {
    let ok: Bool?
    let id: Int?
    let ids: [Int]?
    let message: String?
    let token: String?
}

// MARK: - Catalog

nonisolated struct Brand: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let website: String?
    var filaments: Int?
}

nonisolated struct Vendor: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let url: String?
    let notes: String?
    var spools: Int?
}

nonisolated struct Material: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let density: Double
    let nozzleMin: Int?
    let nozzleMax: Int?
    let bedMin: Int?
    let bedMax: Int?
    let notes: String?
    var filaments: Int?
}

nonisolated struct Location: Codable, Hashable, Identifiable {
    let name: String
    let spools: Int
    var id: String { name }
}

nonisolated struct ItemsResponse<T: Codable>: Codable { let items: [T] }
nonisolated struct LocationsResponse: Codable { let locations: [Location] }

nonisolated struct AppSettings: Codable {
    var currency: String
    var lowStockGrams: Int
    var publicUrl: String
    var detectedUrl: String?
}

// MARK: - Spools

/// A row of the spool list (`listSpools` in the web app).
nonisolated struct SpoolRow: Codable, Hashable, Identifiable {
    let id: Int
    let code: String
    let status: SpoolStatus
    let location: String?
    let initialWeight: Double
    let spoolWeight: Double?
    let price: Double?
    let currency: String?
    let purchaseDate: String?
    let createdAt: Date
    let used: Double
    let remaining: Double
    let lastUsedAt: Date?
    let filamentId: Int
    let filamentName: String
    let colorName: String?
    let colorHex: String?
    let diameter: Double
    let brandName: String?
    let materialName: String?
    let density: Double?
    let vendorName: String?

    var title: String { colorName ?? filamentName }
    var subtitle: String { [brandName, materialName].compactMap { $0 }.joined(separator: " · ") }
}

nonisolated struct SpoolsResponse: Codable { let spools: [SpoolRow] }

nonisolated struct UsageLog: Codable, Hashable, Identifiable {
    let id: Int
    let spoolId: Int
    let grams: Double
    let kind: UsageKind
    let printName: String?
    let note: String?
    let createdAt: Date
}

nonisolated struct NoteSpoolRef: Codable, Hashable {
    let id: Int
    let code: String
}

nonisolated struct FilamentNote: Codable, Hashable, Identifiable {
    let id: Int
    let filamentId: Int
    let spoolId: Int?
    let body: String
    let createdAt: Date
    let spool: NoteSpoolRef?
}

nonisolated struct Filament: Codable, Hashable, Identifiable {
    let id: Int
    let brandId: Int?
    let materialId: Int?
    let name: String
    let colorName: String?
    let colorHex: String?
    let diameter: Double
    let nominalWeight: Double
    let spoolWeight: Double?
    let nozzleMin: Int?
    let nozzleMax: Int?
    let bedMin: Int?
    let bedMax: Int?
    let dryingTemp: Int?
    let dryingHours: Double?
    let maxSpeed: Int?
    let fan: String?
    let productUrl: String?
    let imageUrl: String?
    let prusamentGoodsId: Int?
    let rating: Int?
    let archived: Bool
    let brand: Brand?
    let material: Material?

    var title: String { colorName ?? name }
    var subtitle: String { [brand?.name, material?.name].compactMap { $0 }.joined(separator: " · ") }
    var effectiveNozzle: (Int?, Int?) { (nozzleMin ?? material?.nozzleMin, nozzleMax ?? material?.nozzleMax) }
    var effectiveBed: (Int?, Int?) { (bedMin ?? material?.bedMin, bedMax ?? material?.bedMax) }
    var density: Double { material?.density ?? 1.24 }
}

nonisolated struct SpoolDetail: Codable, Hashable, Identifiable {
    let id: Int
    let filamentId: Int
    let code: String
    let prusamentSpoolId: String?
    let initialWeight: Double
    let spoolWeight: Double?
    let price: Double?
    let currency: String?
    let vendorId: Int?
    let purchaseDate: String?
    let purchaseUrl: String?
    let manufactureDate: String?
    let lengthM: Double?
    let diameterTolerance: Double?
    let diameterSd: Double?
    let ovality: Double?
    let location: String?
    let status: SpoolStatus
    let openedAt: Date?
    let notes: String?
    let createdAt: Date
    let filament: Filament
    let vendor: Vendor?
    let usage: [UsageLog]
    let used: Double
    let remaining: Double
    let qrUrl: String
    let filamentNotes: [FilamentNote]

    var pricePerGram: Double? { price.map { $0 / max(initialWeight, 1) } }
    var currencyCode: String { currency ?? "EUR" }
}

nonisolated struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

// MARK: - Filaments

nonisolated struct FilamentRow: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let colorName: String?
    let colorHex: String?
    let diameter: Double
    let nozzleMin: Int?
    let nozzleMax: Int?
    let bedMin: Int?
    let bedMax: Int?
    let rating: Int?
    let imageUrl: String?
    let brandName: String?
    let materialName: String?
    let spoolCount: Int
    let activeCount: Int
    let remaining: Double

    var title: String { colorName ?? name }
    var subtitle: String { [brandName, materialName].compactMap { $0 }.joined(separator: " · ") }
}

nonisolated struct FilamentsResponse: Codable { let filaments: [FilamentRow] }

nonisolated struct FilamentOption: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let colorName: String?
    let colorHex: String?
    let brandName: String?
    let materialName: String?
    let nominalWeight: Double
    let spoolWeight: Double?

    var label: String {
        let prefix = [brandName, materialName].compactMap { $0 }.joined(separator: " ")
        let title = colorName ?? name
        return prefix.isEmpty ? title : "\(prefix) – \(title)"
    }
}

nonisolated struct FilamentOptionsResponse: Codable { let filaments: [FilamentOption] }

nonisolated struct FilamentSpoolUsage: Codable, Hashable {
    let grams: Double
    let kind: UsageKind
    let createdAt: Date
}

nonisolated struct FilamentSpool: Codable, Hashable, Identifiable {
    let id: Int
    let code: String
    let initialWeight: Double
    let price: Double?
    let currency: String?
    let purchaseDate: String?
    let location: String?
    let status: SpoolStatus
    let createdAt: Date
    let vendor: Vendor?
    let usage: [FilamentSpoolUsage]

    var used: Double { usage.reduce(0) { $0 + $1.grams } }
    var remaining: Double { initialWeight - used }
}

nonisolated struct FilamentDetail: Codable, Hashable, Identifiable {
    let filament: Filament
    let notes: [FilamentNote]
    let spools: [FilamentSpool]
    var id: Int { filament.id }

    init(from decoder: Decoder) throws {
        filament = try Filament(from: decoder)
        let c = try decoder.container(keyedBy: DynamicKey.self)
        notes = try c.decode([FilamentNote].self, forKey: DynamicKey("notes"))
        spools = try c.decode([FilamentSpool].self, forKey: DynamicKey("spools"))
    }

    func encode(to encoder: Encoder) throws {}
}

// MARK: - Dashboard

nonisolated struct RecentPrint: Codable, Hashable, Identifiable {
    let id: Int
    let grams: Double
    let printName: String?
    let createdAt: Date
    let spoolId: Int
    let code: String
    let colorName: String?
    let filamentName: String
    let colorHex: String?
    let materialName: String?
    let brandName: String?
}

nonisolated struct MaterialUsage: Codable, Hashable, Identifiable {
    let material: String
    let grams: Double
    var id: String { material }
}

nonisolated struct Dashboard: Codable {
    let spoolCount: Int
    let remaining: Double
    let value: Double
    let low: [SpoolRow]
    let recent: [RecentPrint]
    let byMaterial: [MaterialUsage]
    let prints30: Int
    let used30: Double
    let currency: String
    let lowStockGrams: Int
}

// MARK: - Scan & Prusament

nonisolated struct ScanResolution: Codable {
    let kind: String
    let id: Int?
    let url: String?
    let error: String?
}

nonisolated struct PrusamentPrice: Codable, Hashable {
    let amount: Double
    let currency: String
}

nonisolated struct PrusamentPreview: Codable {
    struct FilamentInfo: Codable {
        let brand: String?
        let material: String?
        let name: String
        let colorName: String?
        let colorHex: String?
        let diameter: Double
        let nominalWeight: Double
        let spoolWeight: Double?
        let nozzleMin: Int?
        let nozzleMax: Int?
        let bedMin: Int?
        let bedMax: Int?
        let imageUrl: String?
    }

    struct SpoolInfo: Codable {
        let prusamentSpoolId: String
        let initialWeight: Double
        let spoolWeight: Double?
        let lengthM: Double?
        let manufactureDate: String?
        let diameterTolerance: Double?
        let diameterSd: Double?
        let ovality: Double?
    }

    struct ExistingFilament: Codable {
        let id: Int
        let name: String
    }

    let existingSpoolId: Int?
    let url: String?
    let filament: FilamentInfo?
    let spool: SpoolInfo?
    let existingFilament: ExistingFilament?
    let price: PrusamentPrice?
}
