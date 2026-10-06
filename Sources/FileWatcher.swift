import Foundation

/// Calls `onChange` on the main queue whenever the file at `url` is modified,
/// including atomic saves that replace the file with a new one.
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var needsRearm = false

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        arm()
    }

    deinit {
        pending?.cancel()
        source?.cancel()
    }

    private func arm(attemptsLeft: Int = 25) {
        source?.cancel()
        source = nil
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // Mid-replace, or gone for good: keep trying for a few seconds.
            guard attemptsLeft > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.arm(attemptsLeft: attemptsLeft - 1)
                if self?.source != nil { self?.onChange() }
            }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self, unowned source] in
            self?.fileChanged(replaced: !source.data.isDisjoint(with: [.delete, .rename]))
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    private func fileChanged(replaced: Bool) {
        // A replaced file needs a fresh descriptor; the old one points at the dead inode.
        needsRearm = needsRearm || replaced
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if needsRearm {
                needsRearm = false
                arm()
            }
            onChange()
        }
        pending = work
        // Debounce: writers often emit several events per save.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }
}
