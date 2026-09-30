public struct APDisplayState: Hashable, Sendable {
    public var visibility: Bool
    public var visibilityLocked: Bool

    public init(visibility: Bool, visibilityLocked: Bool) {
        self.visibility = visibility
        self.visibilityLocked = visibilityLocked
    }
}
