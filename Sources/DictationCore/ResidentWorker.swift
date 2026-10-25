import Foundation
import Darwin

/// One private child, serialized requests, and cancellation independent of its blocked reader.
public final class ResidentWorker {
    private let queue = DispatchQueue(label: "dictation.worker", qos: .userInitiated)
    private let lock = NSLock()
    private var generation = 0
    private var process: Process?
    // Pipe state is exclusively owned by queue.
    private var session: (process: Process, input: FileHandle, output: FileHandle, generation: Int)?
    private var buffered = Data()
    private let executable: URL
    private let arguments: [String]
    public init(executable: URL, arguments: [String]) {
        self.executable = executable; self.arguments = arguments
    }
    public func cancel() {
        lock.lock(); generation += 1
        if let process, process.isRunning { process.terminate() }
        lock.unlock()
    }
    private func epoch() -> Int { lock.lock(); defer { lock.unlock() }; return generation }
    private func check(_ value: Int) throws {
        guard epoch() == value else { throw Failure.cancelled }
    }
    public enum Failure: Error { case cancelled, unavailable, invalidReply }
    public func warm() throws {
        let value = epoch()
        try queue.sync { try ensure(value) }
    }
    public func request(_ object: [String: String]) throws -> String {
        let value = epoch()
        return try queue.sync {
            do {
                try ensure(value)
                guard let session else { throw Failure.unavailable }
                var data = try JSONSerialization.data(withJSONObject: object); data.append(10)
                // Suppress SIGPIPE for this pipe only; a dead child becomes a thrown write error.
                _ = fcntl(session.input.fileDescriptor, F_SETNOSIGPIPE, 1)
                try session.input.write(contentsOf: data)
                let reply = try readReply(session.output)
                try check(value)
                guard reply["type"] as? String == "result", reply["id"] as? String == object["id"],
                      let text = reply["text"] as? String else { throw Failure.invalidReply }
                return text
            } catch { dispose(); throw error }
        }
    }
    private func dispose() {
        guard let old = session else { return }
        try? old.input.close()
        if old.process.isRunning { old.process.terminate() }
        old.process.waitUntilExit()
        try? old.output.close()
        lock.lock(); if process === old.process { process = nil }; lock.unlock()
        session = nil; buffered.removeAll(keepingCapacity: false)
    }
    private func ensure(_ value: Int) throws {
        try check(value)
        if let session, session.generation == value, session.process.isRunning { return }
        dispose()
        let child = Process(), input = Pipe(), output = Pipe()
        child.executableURL = executable; child.arguments = arguments
        child.standardInput = input; child.standardOutput = output; child.standardError = FileHandle.nullDevice
        lock.lock()
        guard generation == value else { lock.unlock(); throw Failure.cancelled }
        do { try child.run(); process = child; lock.unlock() }
        catch { lock.unlock(); throw error }
        session = (child, input.fileHandleForWriting, output.fileHandleForReading, value)
        do {
            guard try readReply(output.fileHandleForReading)["type"] as? String == "ready" else { throw Failure.invalidReply }
            try check(value)
        } catch { dispose(); throw error }
    }
    private func readReply(_ handle: FileHandle) throws -> [String: Any] {
        while true {
            if let end = buffered.firstIndex(of: 10) {
                let line = buffered.prefix(upTo: end)
                let result = try JSONSerialization.jsonObject(with: line)
                buffered.removeSubrange(...end)
                guard let object = result as? [String: Any] else { throw Failure.invalidReply }
                return object
            }
            guard buffered.count <= 1024 * 1024 else { throw Failure.invalidReply }
            let data = handle.availableData
            guard !data.isEmpty else { throw Failure.unavailable }
            buffered.append(data)
        }
    }
    /// Call after cancel, once all caller jobs have finished.
    public func close() { cancel(); queue.sync { dispose() } }
}
