# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- `DanmuConfig` values are validated by `DanmuEngine` at runtime in every build
  mode instead of relying on debug-only assertions for scheduling invariants.
- `maxQueueSize` now bounds the total waiting set, including entries sent
  before layout and entries waiting for a free lane.
- Existing active entries keep the effective speed captured when they were
  activated; changing the default config speed affects only later activations.
- Runtime queue-limit reductions first use newly available lanes, then trim
  any remaining overflow from the waiting-queue tail.
- CI verifies both Flutter 3.27.0 (declared minimum) and Flutter 3.44.8.

### Fixed

- Prevented StatefulWidget danmu children from inheriting another entry's
  State after an earlier Stack child leaves.
- Prevented zero-lane / zero-size layouts from keeping an idle Ticker running.
- Prevented an older widget from detaching a newer `DanmuHandle` attachment.
- Prevented messages accepted while layout was unavailable from being silently
  lost when valid geometry returned to an already-full waiting queue.
- Prevented pause/resume wall-clock gaps from turning into motion jumps.

### Testing

- Added regression coverage for render identity, zero-size and zero-lane
  recovery, queue capacity and runtime trimming, config validation, runtime
  speed changes, pause/resume, clear, and lane-count resize boundaries.

## [0.1.0] - 2026-09-02

### Added

- `DanmuEngine`: pure scheduling state machine (lane allocation, catch-up
  prevention between entries of different speeds, priority queue, frame
  advancement via time deltas). Testable without a Flutter frame.
- `HaxDanmu` widget: owns only the ticker; lane overlay debug aid; runtime
  config updates through `didUpdateWidget`; idle ticker auto-stop.
- `DanmuHandle`: command bridge (`send` / `play` / `pause` / `clear`) whose
  methods are safe no-ops once the widget detaches.
- Scrolling (right-to-left) danmu with per-entry speed and lane hints.
