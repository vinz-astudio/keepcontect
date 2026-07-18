# Compact Viewport Diagnostics Design

## Problem

The current diagnostics exporter pretty-prints up to 120 full snapshots. Every snapshot repeats the full URL, launch metadata, viewport data, four element geometries and their computed styles. The copied text can become too large for reliable chat transport, while it still omits the two facts now needed on the affected iPhone: whether `kc-ios-standalone` is present and how `100vh`/`100dvh` resolve in pixels.

## Considered approaches

1. **Only reduce the buffer size.** Small code change, but repeated snapshots and irrelevant/full-URL fields remain, and the missing viewport-unit evidence is still absent.
2. **Compact default export plus explicit full export.** Recommended. It preserves forensic history locally, gives the user a chat-safe diagnostic by default, and adds the exact physical-device evidence needed by the parent viewport task.
3. **Upload diagnostics to a server.** Rejected: unnecessary privacy, authentication, retention and operational scope for a local viewport investigation.

## Design

### Capture contract

Each trace continues to retain the existing full local record. Add these device-runtime fields to `display`:

- `iosStandaloneClass`: whether `<html>` contains `kc-ios-standalone`.
- `viewportUnits.vhPx`: computed pixel height of a hidden `height:100vh` probe.
- `viewportUnits.dvhPx`: computed pixel height of a hidden `height:100dvh` probe, or `null` when unsupported.

The probes are created, measured and removed during collection. Diagnostics remain local and must never break app rendering.

### Compact export contract

`exportCompactViewportTraceText()` returns pretty JSON with:

- format/version identifier and export time;
- total stored count, included state count and latest suspects;
- at most 12 state-changing snapshots, newest first;
- only event identity, essential height metrics, visual viewport metrics, display/standalone/safe-area/unit results, root/home/tabbar rectangles and derived gaps.

Snapshots with the same diagnostic state signature are collapsed even if their event labels differ. The compact output excludes full URL/query/hash, launch metadata, page element details and repeated full computed-style objects.

### Full export contract

Keep the existing complete JSON export as `exportFullViewportTraceText()`. It remains available through a secondary, clearly labelled “Copy full log” action for rare lifecycle investigations.

### UI

The primary button becomes “Copy compact diagnostics” / “复制精简诊断”. A secondary “Copy full log” / “复制完整日志” button remains beside Clear. Status text distinguishes compact and full copies. The help copy tells the user to send the compact result first.

## Failure handling

Clipboard fallback remains unchanged. Probe or storage failures return `null`/empty diagnostics rather than affecting the app. Compact serialization works from supplied entries so it can be tested without browser storage.

## Verification

- RED-first tests prove compact export is bounded, deduplicates identical states, excludes URLs/full styles and contains standalone/unit evidence.
- A source contract test proves the card uses compact export as the primary action and retains an explicit full action.
- Focused tests, full Vitest, TypeScript and production build must pass.
- This tool change does not claim that the 47pt viewport defect itself is fixed.
