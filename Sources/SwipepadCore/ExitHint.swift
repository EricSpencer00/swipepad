import Foundation

public struct ExitHint: Sendable {
    public static let noiseCount = 6
    public static let window = 2.0
    public static let cooldown = 60.0
    public static let message = "Press Esc or double-tap ⌘ to exit SwipeType swipe typing"

    private var recent: [Double] = []
    private var lastShown: Double?

    public init() {}

    public mutating func record(at time: Double) -> Bool {
        recent.append(time)
        recent.removeAll { $0 < time - Self.window }
        guard recent.count >= Self.noiseCount else { return false }
        if let shown = lastShown, time - shown < Self.cooldown { return false }
        lastShown = time
        recent.removeAll()
        return true
    }

    public mutating func swiped() {
        recent.removeAll()
    }
}
