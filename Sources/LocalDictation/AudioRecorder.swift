import AVFoundation
import Foundation

enum DictationError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var sampleRate = 48000.0
    private var hasTap = false
    private var meter: Float = 0
    var level: Float { lock.lock(); defer { lock.unlock() }; return meter }

    func start() throws {
        cancel()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw DictationError.message("No microphone input is available.")
        }
        sampleRate = format.sampleRate
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            var sum: Float = 0
            for index in 0..<Int(buffer.frameLength) { sum += channel[index] * channel[index] }
            let rms = sqrt(sum / Float(max(1, buffer.frameLength)))
            self.lock.lock()
            self.meter = min(1, rms * 18)
            let count = min(Int(buffer.frameLength), max(0, Int(self.sampleRate * 125) - self.samples.count))
            if count > 0 { self.samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: count)) }
            self.lock.unlock()
        }
        hasTap = true
        engine.prepare()
        do { try engine.start() } catch { cancel(); throw error }
    }

    func stop() throws -> [Float] {
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        lock.lock(); let raw = samples; samples.removeAll(keepingCapacity: false); lock.unlock()
        guard !raw.isEmpty else { return [] }
        guard let from = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let to = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let source = AVAudioPCMBuffer(pcmFormat: from, frameCapacity: AVAudioFrameCount(raw.count)),
              let output = AVAudioPCMBuffer(pcmFormat: to, frameCapacity: AVAudioFrameCount(Double(raw.count) * 16000 / sampleRate + 1024)),
              let converter = AVAudioConverter(from: from, to: to) else {
            throw DictationError.message("Microphone format conversion failed.")
        }
        source.frameLength = AVAudioFrameCount(raw.count)
        raw.withUnsafeBufferPointer { source.floatChannelData![0].update(from: $0.baseAddress!, count: raw.count) }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .endOfStream; return nil }
            supplied = true; state.pointee = .haveData; return source
        }
        if status == .error { throw error ?? DictationError.message("Audio conversion failed.") as NSError }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }

    func cancel() {
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        lock.lock(); samples.removeAll(keepingCapacity: false); meter = 0; lock.unlock()
    }
}
