import Foundation
import DictationCore

struct EngineConfiguration: Decodable {
    let modelPath: String
    let modelSHA256: String
    let testDirectory: String
    static func load() throws -> EngineConfiguration {
        guard let url = Bundle.main.url(forResource: "engine", withExtension: "json") else {
            throw DictationError.message("Engine configuration missing. Run scripts/build.py --app.")
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}

final class Transcriber {
    private let lock = NSLock()
    private var worker: ResidentWorker?
    private var current: UUID?

    func cancel() {
        lock.lock(); current = nil; worker?.cancel(); lock.unlock()
    }
    func prepare(id: UUID) { lock.lock(); current = id; lock.unlock() }
    private func getWorker() throws -> ResidentWorker {
        lock.lock(); defer { lock.unlock() }
        if let worker { return worker }
        let config = try EngineConfiguration.load()
        guard let directory = Bundle.main.executableURL?.deletingLastPathComponent() else {
            throw DictationError.message("Local engine missing. Rebuild the app.")
        }
        let created = ResidentWorker(executable: directory.appendingPathComponent("dictation-worker"), arguments: ["--model", config.modelPath])
        worker = created
        return created
    }
    func warm() { try? getWorker().warm() }
    func close() { lock.lock(); let child = worker; lock.unlock(); child?.close() }
    func transcribe(id: UUID, samples: [Float], language: String, vocabulary: String) throws -> String {
        lock.lock(); let valid = current == id; lock.unlock()
        guard valid else { throw DictationError.message("Cancelled.") }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("local-dictation-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temporary) }
        let audio = temporary.appendingPathComponent("speech.wav")
        try Self.wav(samples).write(to: audio, options: .atomic)
        do {
            let text = try getWorker().request(["id": id.uuidString, "audio": audio.path, "language": language, "prompt": String(vocabulary.prefix(1000))])
            lock.lock(); let valid = current == id; lock.unlock()
            guard valid else { throw DictationError.message("Cancelled.") }
            return text
        } catch {
            throw DictationError.message("Local transcription stopped or failed. Try recording again; no text was inserted.")
        }
    }

    static func wav(_ samples: [Float]) -> Data {
        var data = Data()
        func word<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        data.append(contentsOf: "RIFF".utf8); word(UInt32(36 + samples.count * 2))
        data.append(contentsOf: "WAVEfmt ".utf8); word(UInt32(16)); word(UInt16(1)); word(UInt16(1))
        word(UInt32(16000)); word(UInt32(32000)); word(UInt16(2)); word(UInt16(16))
        data.append(contentsOf: "data".utf8); word(UInt32(samples.count * 2))
        for sample in samples { word(Int16(max(-1, min(1, sample)) * 32767)) }
        return data
    }
}
