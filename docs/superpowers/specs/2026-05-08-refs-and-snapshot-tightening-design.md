# Refs and Snapshot Tightening — Design

**Date:** 2026-05-08
**Status:** Draft, awaiting review
**Branch:** `feat/describe-refs`

## Summary

Add stable refs (`@N`) to `get_interactive_elements` so agents and CLI users can chain actions without re-finding widgets, and tighten the snapshot output behind opt-in flags so AI agents can request a smaller, less noisy payload. All changes are additive and preserve existing behavior for callers who don't pass new params.

## Motivation

Marionette's existing `get_interactive_elements` returns a flat list of interactive widgets with rich-but-verbose detail (`debugFillProperties` flattened, full bounds, full property dump). Two recurring pain points:

1. **No chaining without re-finding.** Every action call (`tap`, `enter_text`, `scroll_to`) takes a selector by `text`/`key`/`type` and re-runs a finder. If the agent has already inspected the screen and identified the target, it still has to specify a unique selector and risk ambiguity. Chained flows (`tap Save → enter text → tap Confirm`) re-walk the tree on each step.
2. **Token cost.** Default per-entry output is 30–60 tokens, dominated by stringified property dumps that have no value to an LLM agent. A screen with 30 widgets costs ~1.5K tokens just to inspect.

Both fdb (Flutter Debug Bridge) and Playwright MCP solve this with a "snapshot + ref" pattern: one call returns a compact list with stable IDs, and subsequent action calls reference those IDs directly. We adopt the same pattern but layer it onto our existing tool, additively.

## Goals

- Refs (`@N`) attached to every entry, addressable by every action tool.
- Refs persist across separate invocations — chainable from both CLI (separate processes) and MCP (separate tool calls in a turn).
- Optional compact mode that drops noisy property dumps for token-sensitive callers.
- Optional pruning of off-screen / non-current-route / Offstage / zero-size subtrees.
- Optional hard cap with explicit truncation signal.
- Optional viewport-only and scoped (subtree) snapshots.
- Match fdb's built-in coverage (Cupertino + composite Material widgets).
- Zero breakage for existing callers — defaults preserve today's response shape and behavior.

## Non-Goals

- A new `describe` tool (rejected — adds duplication; we evolve `get_interactive_elements` in place additively).
- A new `extractSnapshotEntry` configuration callback (rejected — existing `extractText` / `extractProperties` / `isInteractiveWidget` cover the extension surface).
- Persistent refs across snapshots within a single session (refs are replaced on every `get_interactive_elements` call; stable identity handles drift).
- Web/release-build transport (Spec 3).
- App-declared semantic tools.

## Design

### Tool surface

Single tool: `get_interactive_elements`. New optional parameters, all defaulting to behavior preserved from today:

| Parameter | Type | Default | Effect |
|-----------|------|---------|--------|
| `compact` | bool | `false` | Drop the flat `debugFillProperties` dump and `extractProperties` keys from each entry, keeping a curated allow-list (`enabled`, `value`, `selected`, `checked`) plus typed core fields. |
| `prune` | bool | `false` | Skip subtrees rooted at `Offstage(offstage: true)`, non-current `ModalRoute`, and zero-size render objects. |
| `limit` | int? | `null` (unlimited) | Hard cap on number of entries; sets `truncated: true` if hit. |
| `viewportOnly` | bool | `false` | Filter to entries whose bounds intersect the screen rect. |
| `scope` | string? | `null` | Root the walk at a ref (e.g. `"@5"`) or selector subtree. When unset, walks from `WidgetsBinding.instance.rootElement`. |

### Per-entry response

All existing keys preserved: `type`, `text`, `key`, `bounds`, `visible`, plus all flat `debugFillProperties` keys and `extractProperties` keys (unless `compact: true`).

New additive fields:

- `ref` — string `"@N"` (always present).
- `parentRef` — string `"@M"` if the nearest in-snapshot ancestor is also included; null otherwise.

### Top-level response

Existing: `{ elements: [...] }`.

New optional fields, only present when relevant:

- `screenName` — string, derived from the current `Scaffold`'s `AppBar`/`SliverAppBar` title text. Helps orient the agent.
- `routeName` — string, derived from the current `ModalRoute.settings.name`.
- `truncated` — bool, present and `true` only when `limit` was hit.

### Built-in interactive list expansion

Add to `MarionetteConfiguration._isBuiltInInteractiveWidget`:

- **Cupertino**: `CupertinoButton`, `CupertinoSwitch`, `CupertinoTextField`, `CupertinoSlider`, `CupertinoListTile`, `CupertinoExpansionTile`, `CupertinoSegmentedControl`, `CupertinoSlidingSegmentedControl`, `CupertinoCheckbox`, `CupertinoRadio`.
- **Material composites previously missing**: `Chip`, `ActionChip`, `FilterChip`, `ChoiceChip`, `InputChip`, `MenuItemButton`, `SubmenuButton`, `SegmentedButton`, `ListTile`, `ExpansionTile`, `Tab`, `BackButton`, `CloseButton`, `RangeSlider`, `InkResponse`, `NavigationBar`, `BottomNavigationBar`, `NavigationRail`, `NavigationDestination`, `DropdownMenu`, `ToggleButtons`.

This is purely additive: nothing previously listed disappears, and `isInteractiveWidget` config callback continues to extend on top.

### Tooltip-as-label fallback

When walking, track the nearest enclosing `Tooltip(message: ...)` ancestor. Interactive widgets without a `text` (e.g. icon buttons) inherit the tooltip's message into their `text` field. Documented in CHANGELOG; technically a behavior change for existing callers asserting `text == null` on icon buttons, but unlikely to break anyone in practice.

### Pruning rules (when `prune: true`)

During traversal:

1. **Offstage subtrees.** When `widget.runtimeType == Offstage` and `(widget as Offstage).offstage == true`, skip the subtree.
2. **Non-current route subtrees.** When entering a `StatefulElement` whose `ModalRoute.of(context)` is non-null and not `route.isCurrent`, skip the subtree.
3. **Zero-size render objects.** When `renderObject is RenderBox && renderObject.hasSize && renderObject.size.isEmpty`, skip the subtree.

These match fdb's pruning heuristics.

### Refs

Refs are assigned sequentially (`@1`, `@2`, …) in walk order during the snapshot. They are stored in a session-global table that is replaced on every call to `get_interactive_elements`. The table maps each ref to a **stable identity** record:

```
StableIdentity {
  key:                Key?     // ValueKey if present
  widgetType:         String   // runtimeType.toString()
  ancestorTypePath:   List<String>  // last N non-private ancestor types
  textFingerprint:    String?  // text/label content if any
  siblingIndex:       int      // position among siblings of same type
}
```

This identity is used to re-resolve the ref when an action is dispatched.

### Action tools — `ref` selector

All action tools (`tap`, `double_tap`, `long_press`, `enter_text`, `scroll_to`, `swipe`, `wait`) accept a new selector option `ref`, mutually exclusive with `text`/`key`/`type` via the existing `oneOf` schema:

```json
{ "ref": "@5" }
```

Optional companion parameter:

- `ensureVisible: bool` (default `true`) — when `true`, if the resolved widget is not currently hittable, attempt to scroll it into view and wait for one stable frame before dispatching the action.

#### Resolution flow

When an action is invoked with `{ ref: "@5" }`:

1. Look up the stable identity for `@5`. If no current snapshot exists or `@5` is unknown → error `ref-unknown`.
2. Walk the tree, collecting elements matching the stable identity:
   - Match by `Key` if the identity recorded one.
   - Otherwise match by `(widgetType, ancestorTypePath, textFingerprint)` and select the entry at `siblingIndex`.
3. Resolve to candidates:
   - **0 candidates** → error `ref-stale` (widget unmounted or moved beyond recognition; agent should re-snapshot).
   - **>1 candidates** → error `ref-ambiguous` (rebuild produced multiple matches; agent should re-snapshot).
   - **1 candidate** → proceed.
4. If the candidate is not currently hittable and `ensureVisible: true`:
   - Walk ancestors for the nearest `Scrollable` and call `Scrollable.ensureVisible`.
   - Wait for the next end-of-frame.
   - Re-check hittability.
   - If still not hittable → error `ref-unreachable`.
5. Dispatch the action.

When `ensureVisible: false`, step 4 is skipped and a non-hittable candidate produces `ref-unreachable` immediately.

### Errors (action calls with `ref`)

| Error | Meaning | Recommended caller action |
|-------|---------|--------------------------|
| `ref-unknown` | No active snapshot, or ref not in current table | Call `get_interactive_elements` first |
| `ref-stale` | Identity matched 0 widgets in current tree | Re-snapshot |
| `ref-ambiguous` | Identity matched multiple widgets | Re-snapshot |
| `ref-unreachable` | Could not be made hittable (covered, animating, or `ensureVisible: false`) | Adjust scope, re-snapshot, or retry |

Existing errors for selector-based calls are unchanged.

### Chaining semantics

Refs persist across separate calls because the ref table lives in `marionette_flutter` (in-app), not in the CLI/MCP process:

- **CLI chaining** — separate processes invoking separate VM service extension calls share the in-app table:
  ```
  marionette get-interactive-elements --compact --prune
  marionette tap --ref @5
  marionette enter-text --ref @7 "hello"
  ```
- **MCP chaining** — sequential tool calls in one agent turn share the in-app table similarly.

The MCP server and CLI are stateless between calls. The "session" is the app's lifetime.

## Architecture

### Files (rough plan)

**`marionette_flutter`:**

- `lib/src/services/snapshot_session.dart` (new) — holds the active ref→identity table; cleared on each new snapshot.
- `lib/src/services/stable_identity.dart` (new) — identity construction and matching.
- `lib/src/services/element_tree_finder.dart` — extend `findInteractiveElements` to accept the new params and return reshaped output; add ref assignment, pruning, tooltip inheritance, screen/route detection.
- `lib/src/binding/marionette_configuration.dart` — expand `_isBuiltInInteractiveWidget` list.
- `lib/src/binding/extensions/info_extensions.dart` — add new params on `marionette.interactiveElements`.
- `lib/src/binding/extensions/gesture_extensions.dart` — add `ref` selector to existing action extensions; auto-rescroll-into-view; new error codes.

**`marionette_mcp`:**

- `lib/src/vm_service/tools/inspection_tools.dart` — pass new params through; document additive output shape.
- `lib/src/vm_service/tools/gesture_tools.dart` — extend selector schema with `ref` option (mutually exclusive `oneOf`); pass through `ensureVisible`.

**`marionette_cli`:**

- `lib/src/cli/commands/get_interactive_elements_command.dart` — flags: `--compact`, `--prune`, `--limit N`, `--viewport-only`, `--scope @N|<selector>`.
- `lib/src/cli/commands/<action>_command.dart` (each) — flag: `--ref @N`, `--no-ensure-visible`.

### Data flow (ref-based action)

```
CLI/MCP --[tap with ref=@5]--> VM service ext: marionette.tap
  → snapshot session lookup (@5 → StableIdentity)
  → walk tree, match identity → 1 candidate
  → not hittable: Scrollable.ensureVisible + wait frame
  → dispatch tap on element
  → return success
```

## Testing

### Unit tests

- `stable_identity_test.dart` — identity construction with/without Key; matching logic; siblingIndex disambiguation.
- `snapshot_session_test.dart` — table replaced on new snapshot; lookup returns identity; unknown ref returns null.
- `element_tree_finder_test.dart` — pruning rules (Offstage / non-current-route / zero-size); tooltip inheritance; built-in interactive list coverage; viewportOnly + scope filtering; limit + truncated.

### Integration tests (with `MarionetteBinding`)

- `chain_actions_test.dart` — `get_interactive_elements --compact` → `tap @N` → `enter_text @M` round-trip succeeds.
- `ref_auto_scroll_test.dart` — describe a long list, scroll list off, action with `ref` auto-scrolls back and succeeds.
- `ref_stale_test.dart` — describe → unmount target → action returns `ref-stale`.
- `ref_ambiguous_test.dart` — describe → trigger rebuild duplicating matching subtree → action returns `ref-ambiguous`.
- `ensure_visible_false_test.dart` — describe offscreen item → action with `ensureVisible: false` returns `ref-unreachable`.
- `compact_mode_test.dart` — `compact: true` strips `debugFillProperties` keys, retains allow-list.
- `prune_mode_test.dart` — `prune: true` excludes Offstage / underlying-route / zero-size widgets that the default mode would include.
- `screen_route_name_test.dart` — Scaffold AppBar title surfaces as `screenName`; pushed route name as `routeName`.

### Token-cost smoke

- A representative example app screen rendered with N=30 interactive widgets; assert `compact: true` payload is at least 3× smaller than default.

## Backward Compatibility

- Default response shape is unchanged. New fields (`ref`, `parentRef`, `screenName`, `routeName`, `truncated`) are additive.
- `compact`, `prune`, `limit`, `viewportOnly`, `scope`, `ensureVisible` all default to behavior matching today.
- Tooltip inheritance is the only subtle behavior change in default mode (an icon button that used to surface `text == null` may now surface its tooltip message). CHANGELOG note required.
- Existing selectors (`text`/`key`/`type`) on action tools unchanged. `ref` is a new sibling option in the selector `oneOf`.

## Open Questions

- Should the snapshot session be process-local (one global) or keyed off VM isolate / extension session? Default: one global per binding, replaced on each call. Multi-isolate apps are out of scope for v1.
- Should `parentRef` walk only ancestors that are themselves in the snapshot, or also climb past pruned ancestors? Proposal: nearest in-snapshot ancestor only — `parentRef` is null otherwise.
- `scope` accepting both refs and selectors — keep both, or restrict to refs to avoid double-finder semantics? Proposal: keep both; refs require an active snapshot, selectors don't.

## Out of Scope

- New `describe` tool name (decided: evolve `get_interactive_elements` in place).
- Persistent refs across snapshots (decided: replaced on each call; stable identity handles drift).
- Custom `extractSnapshotEntry` callback (decided: existing config callbacks suffice).
- Web/release transport — addressed by Spec 3 (broker transport).
- App-declared semantic tools — deferred indefinitely.
