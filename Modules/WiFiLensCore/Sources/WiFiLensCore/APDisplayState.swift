struct APDisplayState: Hashable, Sendable {
    var visibility: Bool
    var visibilityLocked: Bool

    init(visibility: Bool, visibilityLocked: Bool) {
        self.visibility = visibility
        self.visibilityLocked = visibilityLocked
    }
}
