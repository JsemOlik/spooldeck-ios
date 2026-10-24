import Foundation
import Testing
@testable import Spooldeck_iOS

@MainActor
struct ScanClassifierTests {
    @Test func prusamentURLs() {
        #expect(ScanClassifier.classify("https://prusament.com/spool/17705/5b1ad8fb47/") == .prusament(url: "https://prusament.com/spool/17705/5b1ad8fb47/"))
        #expect(ScanClassifier.classify("https://www.prusament.com/cs/spool/abc123/") == .prusament(url: "https://www.prusament.com/cs/spool/abc123/"))
        #expect(ScanClassifier.classify("https://evil.example/spool/abc123/") == .unknown("https://evil.example/spool/abc123/"))
    }

    @Test func labelURLsAndCodes() {
        #expect(ScanClassifier.classify("https://spools.example.com/s/3AT4CH") == .code("3AT4CH"))
        #expect(ScanClassifier.classify("http://192.168.1.5:3000/s/3at4ch/") == .code("3AT4CH"))
        #expect(ScanClassifier.classify("  #3at4ch ") == .code("3AT4CH"))
        // 0, O, 1, I and L aren't in the code alphabet.
        #expect(ScanClassifier.classify("O0I1LX") == .unknown("O0I1LX"))
        #expect(ScanClassifier.classify("hello") == .unknown("hello"))
    }
}

@MainActor
struct WeightsTests {
    @Test func lengthMatchesWebApp() {
        // 1 kg of PLA at 1.75 mm is about 335 m (same as estimateLengthM in src/lib/weights.ts).
        let length = Weights.estimateLengthM(grams: 1000, diameterMm: 1.75, density: 1.24)
        #expect(abs(length - 335.3) < 0.5)
        #expect(Weights.estimateLengthM(grams: 0) == 0)
    }

    @Test func costAndPercent() {
        #expect(Weights.cost(grams: 100, price: 25, initialWeight: 1000) == 2.5)
        #expect(Weights.cost(grams: 100, price: nil, initialWeight: 1000) == nil)
        #expect(Weights.remainingPercent(initial: 1000, remaining: -5) == 0)
        #expect(Weights.remainingPercent(initial: 1000, remaining: 250) == 25)
    }

    @Test func ranges() {
        #expect(Format.range(215, 230) == "215–230°C")
        #expect(Format.range(60, 60) == "60°C")
        #expect(Format.range(nil, 90) == "90°C")
        #expect(Format.range(nil, nil) == "—")
    }

    @Test func decimals() {
        #expect("12,5".decimalNormalized == "12.5")
    }
}

@MainActor
struct ServerURLTests {
    @Test func normalisesInput() {
        #expect(AppModel.normalizeServerURL("spools.example.com/")?.absoluteString == "https://spools.example.com")
        #expect(AppModel.normalizeServerURL("http://192.168.1.5:3000")?.absoluteString == "http://192.168.1.5:3000")
        #expect(AppModel.normalizeServerURL("ftp://x") == nil)
        #expect(AppModel.normalizeServerURL("  ") == nil)
    }
}

@MainActor
struct DecodingTests {
    @Test func spoolRow() throws {
        let json = """
        {"spools":[{"id":1,"code":"3AT4CH","status":"opened","location":"Shelf A","initialWeight":1000,"spoolWeight":193,
        "price":29.99,"currency":"EUR","purchaseDate":null,"prusamentSpoolId":null,"createdAt":"2026-10-23T21:40:24.052Z",
        "used":903,"remaining":97,"lastUsedAt":"2026-10-23T21:40:24.528Z","filamentId":1,"filamentName":"Prusament PLA Galaxy Black",
        "colorName":"Galaxy Black","colorHex":"#3b3b45","diameter":1.75,"brandName":"Prusament","materialName":"PLA","density":1.24,"vendorName":"Prusa Store"}]}
        """
        let response = try APIClient.decoder.decode(SpoolsResponse.self, from: Data(json.utf8))
        let spool = try #require(response.spools.first)
        #expect(spool.status == .opened)
        #expect(spool.remaining == 97)
        #expect(spool.subtitle == "Prusament · PLA")
        #expect(spool.lastUsedAt != nil)
    }

    @Test func spoolDetail() throws {
        let json = """
        {"id":1,"filamentId":1,"code":"3AT4CH","prusamentSpoolId":null,"initialWeight":1000,"spoolWeight":193,"price":29.99,
        "currency":"EUR","vendorId":1,"purchaseDate":"2026-10-01","purchaseUrl":null,"manufactureDate":null,"lengthM":null,
        "diameterTolerance":null,"diameterSd":null,"ovality":null,"prusamentRaw":null,"location":"Shelf A","status":"opened",
        "openedAt":"2026-10-23T21:40:24.371Z","notes":"Dry before use","createdAt":"2026-10-23T21:40:24.052Z","updatedAt":"2026-10-23T21:40:24.052Z",
        "filament":{"id":1,"brandId":1,"materialId":1,"name":"Prusament PLA Galaxy Black","colorName":"Galaxy Black","colorHex":"#3b3b45",
          "diameter":1.75,"nominalWeight":1000,"spoolWeight":193,"nozzleMin":null,"nozzleMax":null,"bedMin":null,"bedMax":null,
          "dryingTemp":null,"dryingHours":null,"maxSpeed":null,"fan":null,"productUrl":null,"imageUrl":null,"prusamentGoodsId":null,
          "rating":5,"archived":false,"createdAt":"2026-10-23T21:40:23.000Z","updatedAt":"2026-10-23T21:40:23.000Z",
          "brand":{"id":1,"name":"Prusament","website":null,"createdAt":"2026-10-23T21:40:23.000Z"},
          "material":{"id":1,"name":"PLA","density":1.24,"nozzleMin":205,"nozzleMax":225,"bedMin":50,"bedMax":60,"notes":null,"createdAt":"2026-10-23T21:40:23.000Z"}},
        "vendor":{"id":1,"name":"Prusa Store","url":null,"notes":null,"createdAt":"2026-10-23T21:40:23.000Z"},
        "usage":[{"id":3,"spoolId":1,"grams":-12.5,"kind":"weigh_in","printName":null,"note":"Scale reading","createdAt":"2026-10-23T21:40:24.528Z"}],
        "used":903,"remaining":97,"filamentNotes":[{"id":1,"filamentId":1,"spoolId":1,"body":"Great","createdAt":"2026-10-23T21:40:24.528Z","spool":{"id":1,"code":"3AT4CH"}}],
        "qrUrl":"http://localhost:3000/s/3AT4CH"}
        """
        let spool = try APIClient.decoder.decode(SpoolDetail.self, from: Data(json.utf8))
        #expect(spool.notes == "Dry before use")
        #expect(spool.usage.first?.kind == .weighIn)
        #expect(spool.filamentNotes.first?.spool?.code == "3AT4CH")
        #expect(spool.filament.effectiveNozzle.0 == 205)
        #expect(spool.purchaseDate == "2026-10-01")
    }
}

/// Sample tags from the OpenPrintTag repo (tests/encode_decode/0{1,3,4}_data.bin).
@MainActor
struct OpenPrintTagTests {
    static let prusament = "e140270103ff012f910117550433647461672e6f72672f732f33333463353466303838521cf56170706c69636174696f6e2f766e642e6f70656e7072696e74746167a10218d2bf041b000007d0fcab45f9056a33333463353466303838080009000a76504c412050727573612047616c61787920426c61636b0b6950727573616d656e740e1a68d3c7d7101903e8111903f41219011813443d3e3dff181c9f17ff181df93cf6182218cd182318e1182418aa182518281826183c18271218281828182914182a1840182b18c8182c1864182d183418389f0001ff183b831832fa4134cccdfa43014ccd183c69323730203330203230ff000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000000000fe"
    static let unbranded = "e140270103ff012fc21c0000010d6170706c69636174696f6e2f766e642e6f70656e7072696e74746167a10218eabf041b000007d0fcab465c056a37616232616362353039080009010a6e50455447204a657420426c61636b0e1a68c01ae7101903e81119041a12190118134324292a181c9fff181df93d14182218f0182318d2182419012c182518461826185a1827185a1828183c18291823182a1840182b18c8182c1864182d18d2ff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000bf001901bc01666d79686f6d65ff000000000000000000000000000000000000000000fe"
    static let thirdParty = "e140270103ff012f91010d5502336478746563682e636f6d2f521cff6170706c69636174696f6e2f766e642e6f70656e7072696e74746167a10218dcbf080009150a7819436172626f6e582050454b4b2d412b4346313520426c61636b0b67334458546563680e1a690c5d9b101902ee111902f4121901361343303030181c9f04181f181eff181df93d8f1821f9366618221901681823190186182518781826188c1827183c1828188c1829185a182a183d182b18c6182c1864182d183518346750454b4b2d434618361a000372d0ff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000000000fe"

    private func data(_ hex: String) -> Data {
        Data(stride(from: 0, to: hex.count, by: 2).map { i in
            UInt8(hex[hex.index(hex.startIndex, offsetBy: i)..<hex.index(hex.startIndex, offsetBy: i + 2)], radix: 16)!
        })
    }

    @Test func prusamentTag() throws {
        let tag = try OpenPrintTag.decode(tagMemory: data(Self.prusament), uid: "E0040108662F6FBC")
        #expect(tag.brandName == "Prusament")
        #expect(tag.materialName == "PLA Prusa Galaxy Black")
        #expect(tag.materialType == "PLA")
        #expect(tag.colorName == "Prusa Galaxy Black")
        #expect(tag.colorHex == "#3d3e3d")
        #expect(tag.gtin == 8594173675001)
        #expect(tag.nominalWeight == 1000)
        #expect(tag.actualWeight == 1012)
        #expect(tag.emptyContainerWeight == 280)
        #expect(tag.printTempMin == 205)
        #expect(tag.printTempMax == 225)
        #expect(tag.bedTempMax == 60)
        #expect(abs((tag.density ?? 0) - 1.24) < 0.001)
        #expect(tag.diameter == 1.75)
        #expect(tag.manufacturedDate == Date(timeIntervalSince1970: 1758709719))
        #expect(tag.uri == "https://3dtag.org/s/334c54f088")
        #expect(tag.prusamentURL == "https://prusament.com/spool/334c54f088/")
        #expect(ScanClassifier.classify(tag.prusamentURL!) == .prusament(url: "https://prusament.com/spool/334c54f088/"))
        #expect(tag.consumedWeight == nil)
        #expect(tag.remainingWeight == 1012)
    }

    @Test func longRecordAndAuxRegion() throws {
        // Non-short NDEF record, no brand, and an aux region with consumed weight.
        let tag = try OpenPrintTag.decode(tagMemory: data(Self.unbranded))
        #expect(tag.brandName == nil)
        #expect(tag.materialType == "PETG")
        #expect(tag.consumedWeight == 444)
        #expect(tag.remainingWeight == 606)
        #expect(tag.prusamentURL == nil)
        #expect(tag.uri == nil)
    }

    @Test func thirdPartyTag() throws {
        let tag = try OpenPrintTag.decode(tagMemory: data(Self.thirdParty))
        #expect(tag.brandName == "3DXTech")
        #expect(tag.materialType == "PEKK")
        #expect(tag.materialAbbreviation == "PEKK-CF")
        #expect(tag.colorName == "CarbonX PEKK-A+CF15 Black")
        #expect(tag.displayName == "3DXTech CarbonX PEKK-A+CF15 Black")
        #expect(tag.nominalWeight == 750)
        #expect(tag.prusamentURL == nil)
        #expect(tag.uri == "https://www.3dxtech.com/")
    }

    @Test func rejectsOtherTags() {
        // A tag with only a URI record.
        let uriOnly = data("e140270103" + "10d1010c55046578616d706c652e636f6d" + "fe")
        #expect(throws: OpenPrintTagError.notOpenPrintTag) { try OpenPrintTag.decode(tagMemory: uriOnly) }
        #expect(throws: OpenPrintTagError.notOpenPrintTag) { try OpenPrintTag.decode(tagMemory: Data([0, 0, 0, 0])) }
    }

    @Test func cborIndefiniteAndFloats() throws {
        // {_ 0: "ab" (indefinite text), 1: 1.5 (half), 2: [_ 1, -2]}
        var reader = CBOR.Reader([0xBF, 0x00, 0x7F, 0x61, 0x61, 0x61, 0x62, 0xFF, 0x01, 0xF9, 0x3E, 0x00, 0x02, 0x9F, 0x01, 0x21, 0xFF, 0xFF])
        guard case .map(let map) = try reader.read() else { Issue.record("not a map"); return }
        #expect(map[0]?.text == "ab")
        #expect(map[1]?.double == 1.5)
        #expect(map[2] == .array([.unsigned(1), .negative(1)]))
    }

    @Test func uidOrder() {
        #expect(NFCTagReader.uidString(Data([0xBC, 0x6F, 0x2F, 0x66, 0x08, 0x01, 0x04, 0xE0])) == "E0040108662F6FBC")
        #expect(NFCTagReader.uidString(Data([0xE0, 0x04, 0x01, 0x08, 0x66, 0x2F, 0x6F, 0xBC])) == "E0040108662F6FBC")
    }
}
