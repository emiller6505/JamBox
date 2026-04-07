import CoreServices
import Foundation

/// A Swift wrapper around FSEvents that watches a directory tree for changes.
/// Fires `onChange` whenever files in the watched tree are added, removed,
/// modified, or renamed. Coalesces bursts of events.
final class FolderWatcher {
    /// Called from a background queue whenever the watched folder changes.
    /// Set this before calling `start(watching:)`.
    var onChange: () -> Void = {}

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.jambox.FolderWatcher", qos: .utility)

    deinit {
        stop()
    }

    /// Start watching `url` recursively. Stops any existing watch first.
    func start(watching url: URL) {
        stop()

        // FSEventStream takes a C callback function pointer, not a Swift closure.
        // We pass `self` through the `info` context pointer so the C callback
        // can find its way back to our instance.
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let pathsToWatch = [url.path] as CFArray
        let latency: CFTimeInterval = 1.0

        let flags: FSEventStreamCreateFlags = UInt32(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagWatchRoot
        )

        guard let newStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            FolderWatcher.eventCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            print("[JamBox] FSEventStreamCreate failed")
            return
        }

        FSEventStreamSetDispatchQueue(newStream, queue)
        FSEventStreamStart(newStream)
        stream = newStream
    }

    /// Stop watching. Safe to call even if not currently watching.
    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    // MARK: - C Callback

    /// FSEventStream's C callback. Recovers `self` from the context info pointer.
    /// If any event has the root-changed flag (folder deleted/renamed), stops
    /// the watcher. Otherwise, fires `onChange()` ONLY if at least one event
    /// represents an actual content change — file created, removed, renamed,
    /// or modified. Pure inode-metadata touches (atime updates from
    /// AVFoundation reading the playing file) are ignored.
    ///
    /// Without this filter, AVFoundation's read-touches on the currently
    /// playing file caused FSEvents to wake the watcher repeatedly during
    /// playback, kicking off rescans on a tight loop. The rescan path
    /// short-circuits when no real changes occurred, so this was not the
    /// memory sawtooth in card 0005 — but it was still wasted work.
    private static let contentChangeFlags = FSEventStreamEventFlags(
        kFSEventStreamEventFlagItemCreated |
        kFSEventStreamEventFlagItemRemoved |
        kFSEventStreamEventFlagItemRenamed |
        kFSEventStreamEventFlagItemModified
    )

    private static let eventCallback: FSEventStreamCallback = { _, info, numEvents, _, eventFlags, _ in
        guard let info else { return }
        let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()

        let rootChangedFlag = FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
        var sawContentChange = false
        for i in 0..<numEvents {
            let flags = eventFlags[i]
            if flags & rootChangedFlag != 0 {
                watcher.stop()
                return
            }
            if flags & contentChangeFlags != 0 {
                sawContentChange = true
            }
        }

        if sawContentChange {
            watcher.onChange()
        }
    }
}
