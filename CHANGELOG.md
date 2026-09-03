# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-09-03

### Changed

- `DanmuConfig` values are validated by the internal scheduling engine at
  runtime in every build mode instead of relying on debug-only assertions.
- Pre-layout and lane-waiting entries share one bounded waiting queue.
- `maxQueueSize` is now an admission limit: lowering it at runtime no longer
  discards entries that were already accepted.
- Existing active entries keep the effective speed captured when activated;
  changing the default config speed affects only later activations.
- The main package entrypoint now exposes only the host-facing widget API;
  engine state, render identity, and frame scheduling stay internal.
- `DanmuHandle` binding ownership is now private implementation detail; hosts
  only use `send`, `play`, `pause`, and `clear`.
- CI verifies both Flutter 3.27.0 (declared minimum) and Flutter 3.44.8.

### Removed

- Removed the separate `pendingLayout` enqueue result. Waiting for first layout
  and waiting for a free lane both report `DanmuEnqueueResult.queued`.
- Removed `HaxDanmu.background`; compose a background outside the danmu layer.
- Removed `HaxDanmu.onDisposed`; widget lifecycle stays with the owning widget.
- Removed retroactive waiting-queue trimming on runtime config updates.
- Removed public engine diagnostics that were not part of the host-facing API.

### Fixed

- Prevented StatefulWidget danmu children from inheriting another entry's State
  after an earlier Stack child leaves.
- Prevented zero-lane / zero-size layouts from keeping an idle Ticker running.
- Prevented an older widget from detaching a newer `DanmuHandle` owner.
- Prevented entries accepted while layout was unavailable from being silently
  lost when valid geometry returned.
- Prevented pause/resume wall-clock gaps from turning into motion jumps.
- Kept engine geometry aligned with the final constrained Flutter render size.

### Testing

- Regression coverage now focuses on observable scheduling and widget behavior:
  collision safety, priority/FIFO, layout recovery, stable child identity,
  handle rebinding, pause/resume, queue admission, and constraint alignment.
- Removed tests that only existed to lock the deleted queue-trimming strategy or
  pathological floating-point implementation details.

## [0.1.0] - 2026-09-02

### Added

- `DanmuEngine`: pure scheduling state machine (lane allocation, catch-up
  prevention between entries of different speeds, priority queue, frame
  advancement via time deltas).
- `HaxDanmu` widget: owns the ticker and Flutter rendering bridge.
- `DanmuHandle`: command bridge (`send` / `play` / `pause` / `clear`).
- Scrolling (right-to-left) danmu with per-entry speed and lane hints.
