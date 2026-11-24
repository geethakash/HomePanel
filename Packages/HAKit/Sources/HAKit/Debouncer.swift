import Foundation

/// Runs the latest action after the input has been idle for `delay`.
/// Use `flush()` to send the final value right away (e.g. on slider release).
@MainActor
public final class Debouncer {
    private let delay: Duration
    private var task: Task<Void, Never>?
    private var pendingAction: (@MainActor () -> Void)?

    public init(delay: Duration = .milliseconds(150)) {
        self.delay = delay
    }

    public func call(_ action: @escaping @MainActor () -> Void) {
        pendingAction = action
        task?.cancel()
        task = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.fire()
        }
    }

    public func flush() {
        task?.cancel()
        fire()
    }

    public func cancel() {
        task?.cancel()
        pendingAction = nil
    }

    private func fire() {
        let action = pendingAction
        pendingAction = nil
        action?()
    }
}
