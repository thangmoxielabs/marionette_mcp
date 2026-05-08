# Release-Mode Capability Audit

> Generated: 2026-05-08
> Scope: `packages/marionette_flutter/lib` — handlers reachable via broker mode.

## Methodology

Searched for `WidgetInspectorService` and `inspector.` usage across all library
code. Classified each occurrence as:
- **safe** — only used by debug-only code paths or not present at all.
- **needs-fix** — used by handlers reachable via broker; must be replaced.
- **scheduled-followup** — known limitation tracked separately.

## Findings

### WidgetInspectorService

**Result: No occurrences found.**

No file in `packages/marionette_flutter/lib` references `WidgetInspectorService`.

### `inspector.` method calls

**Result: No occurrences found.**

No file references the `inspector` variable or any `FlutterWidgetInspectorService` API.

### `dart:developer` usage

`register_extension_internal.dart` uses `developer.registerExtension` and
`developer.ServiceExtensionResponse`. These APIs are **available in release
builds** — they are VM service extensions, not the widget inspector. Safe.

### `debugFillProperties` / `debug*` APIs

`marionette_configuration.dart` references `debugFillProperties` in a doc
comment only (line 71). The `extractProperties` callback is invoked at runtime
but calls into the user's code, not any debug-only Flutter API. Safe.

### Other potentially debug-stripped APIs

No usage of `debugPrint`, `kDebugMode` guards around handler logic, or
`FlutterErrorDetails` in release-critical paths was found that would block
broker mode. (`FlutterError.reportError` in `register_extension_internal.dart`
is safe — it exists in release builds.)

## Conclusion

**All handler code is release-mode compatible.** No blocking issues found.
Broker transport can proceed without replacing any handler implementations.
