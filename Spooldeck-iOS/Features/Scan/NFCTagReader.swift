import CoreNFC
import Foundation

/// Reads OpenPrintTag chips (ISO 15693 / NFC-V) with Core NFC.
final class NFCTagReader: NSObject, NFCTagReaderSessionDelegate {
    static var isAvailable: Bool { NFCTagReaderSession.readingAvailable }

    private var session: NFCTagReaderSession?
    private var continuation: CheckedContinuation<OpenPrintTag, Error>?

    /// Shows the system NFC sheet and returns the decoded tag. Throws `CancellationError` when the user cancels.
    func scan() async throws -> OpenPrintTag {
        guard Self.isAvailable else { throw NFCReaderError(.readerErrorUnsupportedFeature) }
        finish(.failure(CancellationError()))
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = NFCTagReaderSession(configuration: .init(pollingOption: .iso15693), delegate: self, queue: .main)
            session.alertMessage = "Hold the top of your iPhone near the spool's NFC tag."
            self.session = session
            session.begin()
        }
    }

    private func finish(_ result: Result<OpenPrintTag, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        session = nil
    }

    // The session delivers callbacks on the main queue (see `scan()`).

    nonisolated func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        MainActor.assumeIsolated {
            switch (error as? NFCReaderError)?.code {
            case .readerSessionInvalidationErrorUserCanceled:
                finish(.failure(CancellationError()))
            case .readerErrorSecurityViolation:
                // Builds signed without Config/Spooldeck.entitlements (e.g. by a free personal team).
                finish(.failure(NFCUnavailableError()))
            default:
                finish(.failure(error))
            }
        }
    }

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        MainActor.assumeIsolated {
            guard let first = tags.first, case .iso15693(let tag) = first else {
                session.alertMessage = "That isn't an OpenPrintTag. Try another tag."
                session.restartPolling()
                return
            }
            Task { await read(tag, as: first, in: session) }
        }
    }

    private func read(_ tag: NFCISO15693Tag, as nfcTag: NFCTag, in session: NFCTagReaderSession) async {
        do {
            try await session.connect(to: nfcTag)
            let uid = Self.uidString(tag.identifier)
            let result: OpenPrintTag
            if let message = try? await tag.readNDEF() {
                let records = message.records.map { NDEF.Record(tnf: $0.typeNameFormat.rawValue, type: $0.type, payload: $0.payload) }
                result = try OpenPrintTag.decode(ndefRecords: records, uid: uid)
            } else {
                // Some tags don't report an NDEF message to Core NFC; parse the raw memory instead.
                result = try OpenPrintTag.decode(tagMemory: try await readMemory(tag), uid: uid)
            }
            session.alertMessage = result.displayName
            session.invalidate()
            finish(.success(result))
        } catch {
            session.invalidate(errorMessage: error.localizedDescription)
            finish(.failure(error))
        }
    }

    private func readMemory(_ tag: NFCISO15693Tag) async throws -> Data {
        let info = try await tag.systemInfo(requestFlags: [.highDataRate])
        let blockCount = info.totalBlocks > 0 ? info.totalBlocks : 80
        var memory = Data()
        var block = 0
        while block < blockCount {
            let count = min(8, blockCount - block)
            let blocks = try await tag.readMultipleBlocks(requestFlags: [.highDataRate], blockRange: NSRange(location: block, length: count))
            blocks.forEach { memory.append($0) }
            block += count
        }
        return memory
    }

    /// The UID as printed on OpenPrintTag tools: most significant byte (0xE0) first.
    static func uidString(_ identifier: Data) -> String {
        let bytes = identifier.last == 0xE0 ? Array(identifier.reversed()) : Array(identifier)
        return bytes.map { String(format: "%02X", $0) }.joined()
    }
}

struct NFCUnavailableError: LocalizedError {
    var errorDescription: String? {
        "This build of Spooldeck can't use NFC. It needs the NFC Tag Reading capability, which requires a paid Apple Developer account."
    }
}
