import Foundation

public func sanitizeDraft(_ text: String) -> String {
    let scalars = text.unicodeScalars.map { scalar -> String in
        if CharacterSet.whitespacesAndNewlines.contains(scalar) { return " " }
        if CharacterSet.controlCharacters.contains(scalar) { return "" }
        return String(scalar)
    }.joined()
    return scalars.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

public enum AudioGate {
    public static func accepts(_ samples: [Float], sampleRate: Double) -> Bool {
        guard sampleRate.isFinite, sampleRate > 0,
              Double(samples.count) / sampleRate >= 0.35,
              samples.allSatisfy({ $0.isFinite }) else { return false }
        let frame = max(1, Int(sampleRate * 0.02))
        var voiced = 0
        for start in stride(from: 0, to: samples.count, by: frame) {
            let end = min(start + frame, samples.count)
            let power = samples[start..<end].reduce(0.0) { $0 + Double($1 * $1) } / Double(end - start)
            if power.squareRoot() > 0.008 { voiced += end - start }
        }
        return Double(voiced) / sampleRate >= 0.2
    }
}

public struct SessionGate {
    private var current: UUID?
    private var target: Int32?
    public init() {}
    public mutating func begin(pid: Int32) -> UUID {
        let token = UUID()
        current = token
        target = pid
        return token
    }
    public mutating func cancel() { current = nil; target = nil }
    public func accepts(token: UUID, pid: Int32) -> Bool { current == token && target == pid }
}

/// Use the event's right-side modifier bit, not a separate global key-state query.
/// A query at the event tap can describe a different point in event delivery.
public struct RightOptionState {
    private var held = false
    public init() {}
    public mutating func reset() { held = false }
    public mutating func update(keyCode: Int64, flags: UInt64) -> Bool? {
        guard keyCode == 61 else { return nil }
        // Hardware events expose side bits; synthetic/remote events may only
        // expose the aggregate Option mask. The event keyCode still selects Right Option.
        let sides = flags & 0x60
        let next = sides != 0 ? (sides & 0x40 != 0) : (flags & 0x80000 != 0)
        guard next != held else { return nil }
        held = next
        return next
    }
}
