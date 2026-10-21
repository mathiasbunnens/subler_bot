import Foundation

/// One shared, non-cancelling drain for every native termination entry point.
@MainActor
public final class GracefulTermination {
    private var task: Task<Void, Never>?
    public var isRequested: Bool { task != nil }
    public init() {}

    @discardableResult
    public func request(drain: @escaping @MainActor () async -> Void,
                        finish: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        if let task { return task }
        let task = Task { await drain(); await finish() }
        self.task = task
        return task
    }
}
