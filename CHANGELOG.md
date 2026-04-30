# Changelog

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
