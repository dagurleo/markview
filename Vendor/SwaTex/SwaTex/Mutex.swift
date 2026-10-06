import os

/// Markview: a stand-in for `Synchronization.Mutex`, which needs macOS 15, so that
/// SwaTex runs on macOS 14. It has the same shape as the parts SwaTex uses.
public struct Mutex<Value: ~Copyable>: ~Copyable, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private let value: UnsafeMutablePointer<Value>

    public init(_ initialValue: consuming sending Value) {
        value = .allocate(capacity: 1)
        value.initialize(to: initialValue)
    }

    deinit {
        value.deinitialize(count: 1)
        value.deallocate()
    }

    public borrowing func withLock<Result: ~Copyable, E: Error>(
        _ body: (inout sending Value) throws(E) -> sending Result
    ) throws(E) -> sending Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value.pointee)
    }
}
