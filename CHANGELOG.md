# Changelog

## v0.2.0

### Added

- `RecursiveWatchBackend` with `.dispatchSource`, `.fsevents`, and `.automatic`
- macOS FSEvents recursive backend that watches a directory tree with one stream instead of one file descriptor per subdirectory
- `RecursiveWatchOptions(..., backend:)` initializer for explicit backend selection while preserving the existing initializer
- `FSWatcherStress` Swift stress runner for large recursive trees and backend comparisons
- FSEvents tests for directory ceiling bypass, deep filtered files, max depth, exclude patterns, move-in/rename events, and automatic backend fallback

### Changed

- `RecursiveWatchOptions()` still defaults to `.dispatchSource` for source compatibility; Zipic-style large macOS trees can opt into `.fsevents`
- FSEvents filtered events use a bounded recursive snapshot under the changed directory so coalesced parent-directory events do not miss deep files
- Multi-recursive tests now guard shared sets with locks to avoid concurrent callback crashes in full-suite runs

## v0.1.0

### Added

- `RecursiveWatchOptions.maxWatchedDirectories` (default: 256) — FD ceiling that prevents deep directory trees from exhausting file descriptors in sandboxed processes
- `RecursiveDirectoryWatcher.start(on:)` / `startAsync(on:)` — async launch APIs that run the recursive scan on a background queue, safe to call from the main thread
- `FSWatcherError.tooManyWatchers(limit:)` — emitted once per scan when the watcher ceiling is reached
- `FSWatcherError.failedToWatch(URL, underlying:)` — emitted when a single directory fails to open during a recursive scan
- `RecursiveDirectoryWatcherTests` — 7 new tests covering ceiling, async start, backward compatibility, and deep+wide tree stability

### Changed

- `scanAndWatchSubdirectories` rewritten from true recursion to an explicit stack, eliminating call-stack overflow risk on extremely deep trees
- `watchDirectory` failures are no longer silently swallowed — they surface through `onError` for logging and diagnostics
