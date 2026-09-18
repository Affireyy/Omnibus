import Foundation

/// Bridges the app's own Cmd+V handling (see OmnibusApp's replaced Paste
/// command, needed because the OS default just beeps -- see its comment
/// for why) down to whichever view wants first shot at a paste --
/// currently just ComposeBar's message field, which registers/clears
/// this as it gains/loses focus.
final class PasteCoordinator {
    static let shared = PasteCoordinator()
    private init() {}

    /// Returns true if it consumed the paste as a file/image attachment;
    /// nil/false means "nothing registered wants this," so the caller
    /// should perform the normal text paste instead.
    var handler: (() -> Bool)?

    func tryHandle() -> Bool {
        handler?() ?? false
    }
}
