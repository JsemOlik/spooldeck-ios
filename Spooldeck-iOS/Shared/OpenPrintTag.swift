import Foundation

/// The filament data stored on an OpenPrintTag NFC chip (https://openprinttag.org).
/// Only the fields Spooldeck uses are decoded; everything else on the tag is skipped.
nonisolated struct OpenPrintTag: Hashable, Sendable {
    static let mimeType = "application/vnd.openprinttag"

    var uid: String?
    var uri: String?

    var brandName: String?
    var materialName: String?
    var materialType: String?
    var materialAbbreviation: String?
    var gtin: UInt64?
    var brandSpecificInstanceId: String?
    var manufacturedDate: Date?

    var nominalWeight: Double?
    var actualWeight: Double?
    var emptyContainerWeight: Double?
    var consumedWeight: Double?
    var colorHex: String?
    var density: Double?
    var diameter: Double?

    var printTempMin: Double?
    var printTempMax: Double?
    var bedTempMin: Double?
    var bedTempMax: Double?
    var dryingTemp: Double?
    var dryingMinutes: Double?

    /// Net filament weight when the spool was full: the measured weight if the tag has one.
    var fullWeight: Double? { actualWeight ?? nominalWeight }

    var remainingWeight: Double? {
        guard let fullWeight else { return nil }
        return max(0, fullWeight - (consumedWeight ?? 0))
    }

    var displayName: String {
        [brandName, materialName ?? materialType].compactMap { $0 }.joined(separator: " ").nilIfEmpty ?? "Unknown filament"
    }

    /// The material name without its leading type, e.g. "PLA Prusa Galaxy Black" → "Prusa Galaxy Black".
    var colorName: String? {
        guard let materialName else { return nil }
        for prefix in [materialAbbreviation, materialType].compactMap({ $0 }) where materialName.hasPrefix(prefix + " ") {
            return String(materialName.dropFirst(prefix.count + 1))
        }
        return materialName
    }

    /// Prusament tags carry the spool id that's also in the spool's QR code.
    var prusamentURL: String? {
        guard brandName?.lowercased() == "prusament",
              let id = brandSpecificInstanceId?.lowercased(),
              id.wholeMatch(of: #/[0-9a-f]{6,32}/#) != nil
        else { return nil }
        return "https://prusament.com/spool/\(id)/"
    }
}

nonisolated enum OpenPrintTagError: LocalizedError, Equatable {
    case notOpenPrintTag
    case corrupt

    var errorDescription: String? {
        switch self {
        case .notOpenPrintTag: "This NFC tag doesn't have OpenPrintTag data on it."
        case .corrupt: "The OpenPrintTag data on this tag couldn't be read."
        }
    }
}

// MARK: - Decoding

nonisolated extension OpenPrintTag {
    /// Decodes raw tag memory: NFC Type 5 capability container, NDEF TLV, then the NDEF message.
    static func decode(tagMemory memory: Data, uid: String? = nil) throws -> OpenPrintTag {
        let bytes = [UInt8](memory)
        guard bytes.count >= 4, bytes[0] == 0xE1 || bytes[0] == 0xE2 else { throw OpenPrintTagError.notOpenPrintTag }
        // An 8-byte capability container has a zero size byte and the size in bytes 6–7.
        var index = bytes[2] == 0 ? 8 : 4
        while index < bytes.count {
            let type = bytes[index]
            index += 1
            if type == 0x00 { continue }
            if type == 0xFE { break }
            guard index < bytes.count else { break }
            var length = Int(bytes[index])
            index += 1
            if length == 0xFF {
                guard index + 2 <= bytes.count else { throw OpenPrintTagError.corrupt }
                length = Int(bytes[index]) << 8 | Int(bytes[index + 1])
                index += 2
            }
            if type == 0x03 {
                let end = min(bytes.count, index + length)
                return try decode(ndefRecords: NDEF.records(in: Array(bytes[index..<end])), uid: uid)
            }
            index += length
        }
        throw OpenPrintTagError.notOpenPrintTag
    }

    static func decode(ndefRecords records: [NDEF.Record], uid: String? = nil) throws -> OpenPrintTag {
        guard let record = records.first(where: { $0.tnf == 2 && $0.typeString == mimeType }) else {
            throw OpenPrintTagError.notOpenPrintTag
        }
        var tag = try decode(payload: record.payload)
        tag.uid = uid
        tag.uri = records.lazy.compactMap(\.uri).first
        return tag
    }

    /// Decodes the record payload: a CBOR meta map that locates the main and (optional) aux regions.
    static func decode(payload data: Data) throws -> OpenPrintTag {
        let payload = [UInt8](data)
        var reader = CBOR.Reader(payload)
        guard case .map(let meta) = try reader.read() else { throw OpenPrintTagError.corrupt }
        let metaSize = reader.index

        let mainOffset = meta.int(0) ?? metaSize
        let auxOffset = meta.int(2)
        let stops = [mainOffset, auxOffset, payload.count].compactMap { $0 }.sorted()

        func region(at offset: Int, size: Int?) throws -> CBOR.Map {
            guard offset >= 0, offset < payload.count else { throw OpenPrintTagError.corrupt }
            let end = min(payload.count, offset + (size ?? (stops.first { $0 > offset } ?? payload.count) - offset))
            // Regions may carry padding after the map; reading one item ignores it.
            var reader = CBOR.Reader(Array(payload[offset..<end]))
            guard case .map(let map) = try reader.read() else { throw OpenPrintTagError.corrupt }
            return map
        }

        let main = try region(at: mainOffset, size: meta.int(1))
        let aux = try auxOffset.map { try region(at: $0, size: meta.int(3)) }

        var tag = OpenPrintTag()
        tag.gtin = main[4]?.uint
        tag.brandSpecificInstanceId = main[5]?.text
        tag.materialType = main[9]?.uint.flatMap { materialTypes[Int($0)] }
        tag.materialName = main[10]?.text
        tag.brandName = main[11]?.text
        tag.materialAbbreviation = main[52]?.text
        tag.manufacturedDate = main[14]?.double.map { Date(timeIntervalSince1970: $0) }
        tag.nominalWeight = main[16]?.double
        tag.actualWeight = main[17]?.double
        tag.emptyContainerWeight = main[18]?.double
        tag.colorHex = main[19]?.bytes.flatMap(hexColor)
        tag.density = main[29]?.double
        tag.diameter = main[30]?.double ?? 1.75
        tag.printTempMin = main[34]?.double
        tag.printTempMax = main[35]?.double
        tag.bedTempMin = main[37]?.double
        tag.bedTempMax = main[38]?.double
        tag.dryingTemp = main[57]?.double
        tag.dryingMinutes = main[58]?.double
        tag.consumedWeight = aux?[0]?.double
        return tag
    }

    private static func hexColor(_ bytes: Data) -> String? {
        guard bytes.count >= 3 else { return nil }
        return String(format: "#%02x%02x%02x", bytes[bytes.startIndex], bytes[bytes.startIndex + 1], bytes[bytes.startIndex + 2])
    }

    /// data/material_type_enum.yaml in the OpenPrintTag repo.
    static let materialTypes: [Int: String] = [
        0: "PLA", 1: "PETG", 2: "TPU", 3: "ABS", 4: "ASA", 5: "PC", 6: "PCTG", 7: "PP", 8: "PA6", 9: "PA11",
        10: "PA12", 11: "PA66", 12: "CPE", 13: "TPE", 14: "HIPS", 15: "PHA", 16: "PET", 17: "PEI", 18: "PBT",
        19: "PVB", 20: "PVA", 21: "PEKK", 22: "PEEK", 23: "BVOH", 24: "TPC", 25: "PPS", 26: "PPSU", 27: "PVC",
        28: "PEBA", 29: "PVDF", 30: "PPA", 31: "PCL", 32: "PES", 33: "PMMA", 34: "POM", 35: "PPE", 36: "PS",
        37: "PSU", 38: "TPI", 39: "SBS", 40: "OBC", 41: "EVA", 42: "PA612",
    ]
}

// MARK: - NDEF

nonisolated enum NDEF {
    struct Record: Equatable {
        let tnf: UInt8
        let type: Data
        let payload: Data

        var typeString: String? { String(data: type, encoding: .utf8) }

        /// The URL of a well-known "U" record.
        var uri: String? {
            guard tnf == 1, type == Data("U".utf8), let code = payload.first,
                  let rest = String(data: payload.dropFirst(), encoding: .utf8)
            else { return nil }
            return (Int(code) < uriPrefixes.count ? uriPrefixes[Int(code)] : "") + rest
        }
    }

    private static let uriPrefixes = ["", "http://www.", "https://www.", "http://", "https://"]

    /// Parses an NDEF message. Chunked records aren't supported (OpenPrintTag never uses them).
    static func records(in bytes: [UInt8]) throws -> [Record] {
        var records: [Record] = []
        var i = 0
        while i < bytes.count {
            let header = bytes[i]
            i += 1
            let shortRecord = header & 0x10 != 0
            let hasId = header & 0x08 != 0
            guard i < bytes.count else { throw OpenPrintTagError.corrupt }
            let typeLength = Int(bytes[i])
            i += 1
            var payloadLength = 0
            if shortRecord {
                guard i < bytes.count else { throw OpenPrintTagError.corrupt }
                payloadLength = Int(bytes[i])
                i += 1
            } else {
                guard i + 4 <= bytes.count else { throw OpenPrintTagError.corrupt }
                payloadLength = bytes[i..<i + 4].reduce(0) { $0 << 8 | Int($1) }
                i += 4
            }
            var idLength = 0
            if hasId {
                guard i < bytes.count else { throw OpenPrintTagError.corrupt }
                idLength = Int(bytes[i])
                i += 1
            }
            guard i + typeLength + idLength + payloadLength <= bytes.count else { throw OpenPrintTagError.corrupt }
            let type = Data(bytes[i..<i + typeLength])
            i += typeLength + idLength
            let payload = Data(bytes[i..<i + payloadLength])
            i += payloadLength
            records.append(Record(tnf: header & 0x07, type: type, payload: payload))
            if header & 0x40 != 0 { break } // message end
        }
        return records
    }
}

// MARK: - CBOR

/// A small CBOR (RFC 8949) reader covering what OpenPrintTag uses, including indefinite lengths.
nonisolated indirect enum CBOR: Equatable {
    case unsigned(UInt64)
    case negative(UInt64) // -1 - n
    case bytes(Data)
    case text(String)
    case array([CBOR])
    case map(Map)
    case tagged(UInt64, CBOR)
    case simple(UInt8)
    case float(Double)

    struct Map: Equatable {
        var entries: [(key: CBOR, value: CBOR)] = []

        subscript(key: Int) -> CBOR? {
            entries.first { $0.key == .unsigned(UInt64(key)) }?.value
        }

        func int(_ key: Int) -> Int? { self[key]?.uint.map(Int.init) }

        static func == (lhs: Map, rhs: Map) -> Bool {
            lhs.entries.count == rhs.entries.count && zip(lhs.entries, rhs.entries).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        }
    }

    var uint: UInt64? {
        if case .unsigned(let v) = self { return v }
        return nil
    }

    var double: Double? {
        switch self {
        case .unsigned(let v): Double(v)
        case .negative(let v): -1 - Double(v)
        case .float(let v): v
        default: nil
        }
    }

    var text: String? {
        if case .text(let v) = self { return v }
        return nil
    }

    var bytes: Data? {
        if case .bytes(let v) = self { return v }
        return nil
    }

    struct Reader {
        let data: [UInt8]
        private(set) var index = 0

        init(_ data: [UInt8]) {
            self.data = data
        }

        private static let breakCode: UInt8 = 0xFF
        private static let maxDepth = 32

        mutating func read() throws -> CBOR {
            try read(depth: 0)
        }

        private mutating func byte() throws -> UInt8 {
            guard index < data.count else { throw OpenPrintTagError.corrupt }
            defer { index += 1 }
            return data[index]
        }

        private mutating func take(_ count: UInt64) throws -> [UInt8] {
            guard count <= UInt64(data.count - index) else { throw OpenPrintTagError.corrupt }
            defer { index += Int(count) }
            return Array(data[index..<index + Int(count)])
        }

        private mutating func argument(_ info: UInt8) throws -> UInt64 {
            switch info {
            case 0..<24: return UInt64(info)
            case 24: return UInt64(try byte())
            case 25: return try take(2).reduce(0) { $0 << 8 | UInt64($1) }
            case 26: return try take(4).reduce(0) { $0 << 8 | UInt64($1) }
            case 27: return try take(8).reduce(0) { $0 << 8 | UInt64($1) }
            default: throw OpenPrintTagError.corrupt
            }
        }

        private var atBreak: Bool { index < data.count && data[index] == Self.breakCode }

        private mutating func read(depth: Int) throws -> CBOR {
            guard depth < Self.maxDepth else { throw OpenPrintTagError.corrupt }
            let initial = try byte()
            let major = initial >> 5
            let info = initial & 0x1F
            let indefinite = info == 31 && (2...5).contains(major)

            switch major {
            case 0: return .unsigned(try argument(info))
            case 1: return .negative(try argument(info))
            case 2, 3:
                var chunk: [UInt8] = []
                if indefinite {
                    while !atBreak {
                        switch try read(depth: depth + 1) {
                        case .bytes(let part): chunk += part
                        case .text(let part): chunk += Array(part.utf8)
                        default: throw OpenPrintTagError.corrupt
                        }
                    }
                    index += 1
                } else {
                    chunk = try take(try argument(info))
                }
                if major == 2 { return .bytes(Data(chunk)) }
                guard let string = String(bytes: chunk, encoding: .utf8) else { throw OpenPrintTagError.corrupt }
                return .text(string)
            case 4:
                var items: [CBOR] = []
                if indefinite {
                    while !atBreak { items.append(try read(depth: depth + 1)) }
                    index += 1
                } else {
                    for _ in 0..<(try argument(info)) { items.append(try read(depth: depth + 1)) }
                }
                return .array(items)
            case 5:
                var map = Map()
                if indefinite {
                    while !atBreak { map.entries.append((try read(depth: depth + 1), try read(depth: depth + 1))) }
                    index += 1
                } else {
                    for _ in 0..<(try argument(info)) { map.entries.append((try read(depth: depth + 1), try read(depth: depth + 1))) }
                }
                return .map(map)
            case 6:
                return .tagged(try argument(info), try read(depth: depth + 1))
            default:
                switch info {
                case 25: return .float(Double(Float16(bitPattern: UInt16(try argument(25)))))
                case 26: return .float(Double(Float(bitPattern: UInt32(try argument(26)))))
                case 27: return .float(Double(bitPattern: try argument(27)))
                case 24: return .simple(try byte())
                case 0..<24: return .simple(info)
                default: throw OpenPrintTagError.corrupt
                }
            }
        }
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
