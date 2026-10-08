# 1. Native Swift + SwiftUI/AppKit

Status: Accepted · 2026-10-08

## Context
The hard parts are all macOS-native: notch overlay `NSPanel`, global `fn` hotkey via `CGEventTap`, `AXUIElement` automation, low-latency audio, on-device ML (WhisperKit, MLX-Swift, Core ML).

## Decision
Native Swift, SwiftUI for UI, AppKit for the overlay window. Menu-bar app. Apple Silicon only, macOS 14+.

## Consequences
First-class access to every API and ML runtime; small binary and memory. Tauri/Electron would need native bridges for all of the above and avoid none of the signing/TCC requirements. No Intel or non-Mac ports.
