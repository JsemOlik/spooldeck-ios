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
