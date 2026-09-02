# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
