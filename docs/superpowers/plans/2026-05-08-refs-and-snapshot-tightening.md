# Refs and Snapshot Tightening — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add stable refs (`@N`) and optional compact/prune/limit/viewportOnly/scope params to `get_interactive_elements`; teach action tools to accept a `ref` selector with auto-rescroll-into-view. All additive.

**Architecture:** A new `SnapshotSession` holds an in-app ref→`StableIdentity` table populated by every call to `marionette.interactiveElements`. Action handlers gain a `RefMatcher` that re-resolves the identity at use time. The default response shape is preserved; new fields and params are additive.

**Tech Stack:** Dart, Flutter, `package:test`, `flutter_test`. Existing patterns: `WidgetMatcher` for matchers, `registerInternalMarionetteExtension` for VM service handlers.

**Spec:** `docs/superpowers/specs/2026-05-08-refs-and-snapshot-tightening-design.md`

---

## File Structure

**New files:**

- `packages/marionette_flutter/lib/src/services/stable_identity.dart` — `StableIdentity` value type + matcher.
- `packages/marionette_flutter/lib/src/services/snapshot_session.dart` — singleton ref→identity table.
- `packages/marionette_flutter/test/stable_identity_test.dart`
- `packages/marionette_flutter/test/snapshot_session_test.dart`
- `packages/marionette_flutter/test/snapshot_options_test.dart` — params behavior.
- `packages/marionette_flutter/test/ref_matcher_test.dart`
- `packages/marionette_flutter/test/auto_ensure_visible_test.dart`

**Modified files:**

- `packages/marionette_flutter/lib/src/services/element_tree_finder.dart` — accepts `SnapshotOptions`; populates session; pruning; tooltip; screen/route extraction; cap.
- `packages/marionette_flutter/lib/src/services/widget_matcher.dart` — adds `RefMatcher`.
- `packages/marionette_flutter/lib/src/services/widget_finder.dart` — `findHittableElement` honors `RefMatcher` via session lookup.
- `packages/marionette_flutter/lib/src/services/gesture_dispatcher.dart` — auto-rescroll-into-view for `RefMatcher` unless `ensureVisible: false`.
- `packages/marionette_flutter/lib/src/binding/marionette_configuration.dart` — extended built-in interactive list.
- `packages/marionette_flutter/lib/src/binding/extensions/info_extensions.dart` — accept and forward `SnapshotOptions`.
- `packages/marionette_flutter/lib/src/binding/extensions/gesture_extensions.dart` — propagate `ensureVisible`.
- `packages/marionette_mcp/lib/src/vm_service/tools/inspection_tools.dart` — describe new params.
- `packages/marionette_mcp/lib/src/vm_service/tools/gesture_tools.dart` — add `ref` selector to schema.
- `packages/marionette_cli/lib/src/cli/commands/get_interactive_elements_command.dart` — flags.
- All CLI action commands — `--ref` and `--no-ensure-visible`.

---

### Task 1: Verify branch and run baseline tests

**Files:** none.

- [ ] **Step 1: Confirm branch.**

Run: `git status -sb`
Expected: `## feat/describe-refs`

- [ ] **Step 2: Run existing flutter tests to establish baseline.**

Run: `cd packages/marionette_flutter && flutter test`
Expected: all tests pass. Capture count.

- [ ] **Step 3: Run dart analyze.**

Run: `cd packages/marionette_flutter && dart analyze`
Expected: no issues.

---

### Task 2: `StableIdentity` value type

**Files:**
- Create: `packages/marionette_flutter/lib/src/services/stable_identity.dart`
- Test: `packages/marionette_flutter/test/stable_identity_test.dart`

- [ ] **Step 1: Write failing test.**

```dart
// packages/marionette_flutter/test/stable_identity_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/services/stable_identity.dart';

void main() {
  group('StableIdentity', () {
    test('keyed identity matches by key', () {
      const id = StableIdentity(
        key: ValueKey('save-btn'),
        widgetType: 'ElevatedButton',
        ancestorTypePath: ['Scaffold', 'Form'],
        textFingerprint: 'Save',
        siblingIndex: 0,
      );
      const other = StableIdentity(
        key: ValueKey('save-btn'),
        widgetType: 'OutlinedButton',
        ancestorTypePath: [],
        textFingerprint: null,
        siblingIndex: 9,
      );
      expect(id.matchesIdentity(other), isTrue,
          reason: 'When both have same key, only key matters');
    });

    test('keyless identity matches on (type, ancestors, text, siblingIndex)', () {
      const id = StableIdentity(
        key: null,
        widgetType: 'ElevatedButton',
        ancestorTypePath: ['Scaffold', 'Form'],
        textFingerprint: 'Save',
        siblingIndex: 1,
      );
      const equal = StableIdentity(
        key: null,
        widgetType: 'ElevatedButton',
        ancestorTypePath: ['Scaffold', 'Form'],
        textFingerprint: 'Save',
        siblingIndex: 1,
      );
      const diffSibling = StableIdentity(
        key: null,
        widgetType: 'ElevatedButton',
        ancestorTypePath: ['Scaffold', 'Form'],
        textFingerprint: 'Save',
        siblingIndex: 0,
      );
      expect(id.matchesIdentity(equal), isTrue);
      expect(id.matchesIdentity(diffSibling), isFalse);
    });

    test('keyless mismatch when text fingerprint differs', () {
      const a = StableIdentity(
        key: null,
        widgetType: 'ElevatedButton',
        ancestorTypePath: ['Scaffold'],
        textFingerprint: 'Save',
        siblingIndex: 0,
      );
      const b = StableIdentity(
        key: null,
        widgetType: 'ElevatedButton',
        ancestorTypePath: ['Scaffold'],
        textFingerprint: 'Cancel',
        siblingIndex: 0,
      );
      expect(a.matchesIdentity(b), isFalse);
    });
  });
}
```

- [ ] **Step 2: Verify test fails.**

Run: `cd packages/marionette_flutter && flutter test test/stable_identity_test.dart`
Expected: compile error — `stable_identity.dart` not found.

- [ ] **Step 3: Implement `StableIdentity`.**

```dart
// packages/marionette_flutter/lib/src/services/stable_identity.dart
import 'package:flutter/foundation.dart';

/// Identifies a widget across rebuilds without holding an Element reference.
///
/// When [key] is non-null, identity matching uses key alone.
/// Otherwise it uses the tuple (widgetType, ancestorTypePath, textFingerprint,
/// siblingIndex among same-typed siblings under the same parent).
@immutable
class StableIdentity {
  const StableIdentity({
    required this.key,
    required this.widgetType,
    required this.ancestorTypePath,
    required this.textFingerprint,
    required this.siblingIndex,
  });

  final Key? key;
  final String widgetType;
  final List<String> ancestorTypePath;
  final String? textFingerprint;
  final int siblingIndex;

  bool matchesIdentity(StableIdentity other) {
    if (key != null && other.key != null) {
      return key == other.key;
    }
    if (key != null || other.key != null) {
      return false;
    }
    return widgetType == other.widgetType &&
        listEquals(ancestorTypePath, other.ancestorTypePath) &&
        textFingerprint == other.textFingerprint &&
        siblingIndex == other.siblingIndex;
  }
}
```

- [ ] **Step 4: Run tests.**

Run: `cd packages/marionette_flutter && flutter test test/stable_identity_test.dart`
Expected: 3 tests pass.

- [ ] **Step 5: Commit.**

```bash
git add packages/marionette_flutter/lib/src/services/stable_identity.dart \
        packages/marionette_flutter/test/stable_identity_test.dart
git commit -m "feat(marionette_flutter): add StableIdentity value type"
```

---

### Task 3: `SnapshotSession` ref table

**Files:**
- Create: `packages/marionette_flutter/lib/src/services/snapshot_session.dart`
- Test: `packages/marionette_flutter/test/snapshot_session_test.dart`

- [ ] **Step 1: Write failing test.**

```dart
// packages/marionette_flutter/test/snapshot_session_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/services/snapshot_session.dart';
import 'package:marionette_flutter/src/services/stable_identity.dart';

const _id = StableIdentity(
  key: ValueKey('a'),
  widgetType: 'X',
  ancestorTypePath: [],
  textFingerprint: null,
  siblingIndex: 0,
);

void main() {
  setUp(() => SnapshotSession.instance.reset());

  test('lookup returns null for unknown ref', () {
    expect(SnapshotSession.instance.lookup('@1'), isNull);
  });

  test('beginSnapshot replaces table; refs assigned in order', () {
    final s = SnapshotSession.instance;
    s.beginSnapshot();
    final r1 = s.assign(_id);
    final r2 = s.assign(_id);
    expect(r1, '@1');
    expect(r2, '@2');
    expect(s.lookup('@1')?.matchesIdentity(_id), isTrue);

    s.beginSnapshot();
    expect(s.lookup('@1'), isNull);
  });
}
```

- [ ] **Step 2: Verify failure.**

Run: `cd packages/marionette_flutter && flutter test test/snapshot_session_test.dart`
Expected: compile error.

- [ ] **Step 3: Implement.**

```dart
// packages/marionette_flutter/lib/src/services/snapshot_session.dart
import 'package:marionette_flutter/src/services/stable_identity.dart';

/// In-app singleton that holds the most recent snapshot's ref→identity table.
/// Replaced on every call to `marionette.interactiveElements`.
class SnapshotSession {
  SnapshotSession._();
  static final instance = SnapshotSession._();

  final Map<String, StableIdentity> _table = {};
  int _next = 1;

  /// Begin a new snapshot. Clears prior refs.
  void beginSnapshot() {
    _table.clear();
    _next = 1;
  }

  /// Assign a fresh ref to an identity. Returns the ref string (e.g. "@5").
  String assign(StableIdentity identity) {
    final ref = '@$_next';
    _next++;
    _table[ref] = identity;
    return ref;
  }

  /// Look up an identity by ref. Returns null if unknown.
  StableIdentity? lookup(String ref) => _table[ref];

  /// Test-only: clear all state.
  void reset() {
    _table.clear();
    _next = 1;
  }
}
```

- [ ] **Step 4: Run tests.**

Run: `cd packages/marionette_flutter && flutter test test/snapshot_session_test.dart`
Expected: 2 tests pass.

- [ ] **Step 5: Commit.**

```bash
git add packages/marionette_flutter/lib/src/services/snapshot_session.dart \
        packages/marionette_flutter/test/snapshot_session_test.dart
git commit -m "feat(marionette_flutter): add SnapshotSession ref table"
```

---

### Task 4: Expand built-in interactive list

**Files:**
- Modify: `packages/marionette_flutter/lib/src/binding/marionette_configuration.dart`
- Test: `packages/marionette_flutter/test/element_tree_finder_test.dart` (extend existing)

- [ ] **Step 1: Add failing tests for new built-ins.**

Append to `element_tree_finder_test.dart`:

```dart
import 'package:flutter/cupertino.dart';

void _expectInteractiveContains(WidgetTester tester, Type widgetType, String text) async {
  final finder = ElementTreeFinder(const MarionetteConfiguration());
  final elements = finder.findInteractiveElements();
  expect(
    elements.any((e) => e['type'] == widgetType.toString()),
    isTrue,
    reason: 'Expected $widgetType to be recognised as interactive',
  );
}

testWidgets('Cupertino widgets are recognised as interactive', (tester) async {
  await tester.pumpWidget(CupertinoApp(
    home: CupertinoButton(onPressed: () {}, child: const Text('Hi')),
  ));
  final elements = ElementTreeFinder(const MarionetteConfiguration())
      .findInteractiveElements();
  expect(elements.any((e) => e['type'] == 'CupertinoButton'), isTrue);
});

testWidgets('Material composites (Chip, ListTile) are interactive', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Column(children: [
        const Chip(label: Text('Pinned')),
        ListTile(title: const Text('Item'), onTap: () {}),
      ]),
    ),
  ));
  final elements = ElementTreeFinder(const MarionetteConfiguration())
      .findInteractiveElements();
  expect(elements.any((e) => e['type'] == 'Chip'), isTrue);
  expect(elements.any((e) => e['type'] == 'ListTile'), isTrue);
});
```

- [ ] **Step 2: Run tests, verify the Cupertino/composite assertions fail.**

Run: `cd packages/marionette_flutter && flutter test test/element_tree_finder_test.dart`
Expected: failures on the new tests.

- [ ] **Step 3: Expand the built-in list.**

In `marionette_configuration.dart`, replace `_isBuiltInInteractiveWidget` body:

```dart
static bool _isBuiltInInteractiveWidget(Type type) {
  return _materialInteractive.contains(type) ||
      _cupertinoInteractive.contains(type) ||
      _materialComposites.contains(type);
}

static const Set<Type> _materialInteractive = {
  Checkbox, CheckboxListTile, DropdownButton, DropdownButtonFormField,
  ElevatedButton, FilledButton, FloatingActionButton, GestureDetector,
  IconButton, InkWell, OutlinedButton, PopupMenuButton, Radio, RadioListTile,
  Slider, Switch, SwitchListTile, TextButton, TextField, TextFormField,
  ButtonStyleButton,
};

static const Set<Type> _cupertinoInteractive = {
  CupertinoButton, CupertinoSwitch, CupertinoTextField, CupertinoSlider,
  CupertinoListTile, CupertinoCheckbox, CupertinoRadio,
  CupertinoSegmentedControl, CupertinoSlidingSegmentedControl,
};

static const Set<Type> _materialComposites = {
  Chip, ActionChip, FilterChip, ChoiceChip, InputChip, MenuItemButton,
  SubmenuButton, SegmentedButton, ListTile, ExpansionTile, Tab, BackButton,
  CloseButton, RangeSlider, InkResponse, NavigationBar, BottomNavigationBar,
  NavigationRail, NavigationDestination, DropdownMenu, ToggleButtons,
};
```

Add the necessary imports at top:
```dart
import 'package:flutter/cupertino.dart';
```

(Verify each `Type` actually exists in Flutter; remove any that don't compile.)

- [ ] **Step 4: Run tests.**

Run: `cd packages/marionette_flutter && flutter test test/element_tree_finder_test.dart`
Expected: all tests pass.

- [ ] **Step 5: Commit.**

```bash
git add packages/marionette_flutter/lib/src/binding/marionette_configuration.dart \
        packages/marionette_flutter/test/element_tree_finder_test.dart
git commit -m "feat(marionette_flutter): expand built-in interactive widgets (Cupertino + composites)"
```

---

### Task 5: `SnapshotOptions` model + `findInteractiveElements` accepts options

**Files:**
- Create: `packages/marionette_flutter/lib/src/services/snapshot_options.dart`
- Modify: `packages/marionette_flutter/lib/src/services/element_tree_finder.dart`
- Test: `packages/marionette_flutter/test/snapshot_options_test.dart`

- [ ] **Step 1: Write failing test.**

```dart
// packages/marionette_flutter/test/snapshot_options_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/services/snapshot_options.dart';

void main() {
  test('SnapshotOptions defaults preserve old behavior', () {
    const opts = SnapshotOptions();
    expect(opts.compact, isFalse);
    expect(opts.prune, isFalse);
    expect(opts.limit, isNull);
    expect(opts.viewportOnly, isFalse);
    expect(opts.scope, isNull);
  });

  test('fromJson parses every field', () {
    final opts = SnapshotOptions.fromJson({
      'compact': 'true',
      'prune': 'true',
      'limit': '50',
      'viewportOnly': 'true',
      'scope': '@5',
    });
    expect(opts.compact, isTrue);
    expect(opts.prune, isTrue);
    expect(opts.limit, 50);
    expect(opts.viewportOnly, isTrue);
    expect(opts.scope, '@5');
  });
}
```

- [ ] **Step 2: Verify failure.**

Run: `cd packages/marionette_flutter && flutter test test/snapshot_options_test.dart`
Expected: compile error.

- [ ] **Step 3: Implement.**

```dart
// packages/marionette_flutter/lib/src/services/snapshot_options.dart
class SnapshotOptions {
  const SnapshotOptions({
    this.compact = false,
    this.prune = false,
    this.limit,
    this.viewportOnly = false,
    this.scope,
  });

  final bool compact;
  final bool prune;
  final int? limit;
  final bool viewportOnly;
  final String? scope;

  factory SnapshotOptions.fromJson(Map<String, dynamic> p) {
    bool b(String k) => p[k] == 'true' || p[k] == true;
    int? n(String k) => p[k] == null ? null : int.parse(p[k].toString());
    return SnapshotOptions(
      compact: b('compact'),
      prune: b('prune'),
      limit: n('limit'),
      viewportOnly: b('viewportOnly'),
      scope: p['scope']?.toString(),
    );
  }
}
```

Modify `element_tree_finder.dart`:

```dart
List<Map<String, dynamic>> findInteractiveElements({
  SnapshotOptions options = const SnapshotOptions(),
}) {
  // existing body — options unused for now (wired in subsequent tasks).
  ...
}
```

- [ ] **Step 4: Run all flutter tests; nothing should break.**

Run: `cd packages/marionette_flutter && flutter test`
Expected: all pass.

- [ ] **Step 5: Commit.**

```bash
git add packages/marionette_flutter/lib/src/services/snapshot_options.dart \
        packages/marionette_flutter/lib/src/services/element_tree_finder.dart \
        packages/marionette_flutter/test/snapshot_options_test.dart
git commit -m "feat(marionette_flutter): introduce SnapshotOptions on findInteractiveElements"
```

---

### Task 6: Assign refs + parentRef during traversal

**Files:**
- Modify: `packages/marionette_flutter/lib/src/services/element_tree_finder.dart`
- Test: `packages/marionette_flutter/test/element_tree_finder_test.dart` (extend)

- [ ] **Step 1: Write failing test.**

```dart
testWidgets('snapshot assigns sequential refs and parentRef', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Column(children: [
        ElevatedButton(onPressed: () {}, child: const Text('A')),
        ElevatedButton(onPressed: () {}, child: const Text('B')),
      ]),
    ),
  ));
  final elements = ElementTreeFinder(const MarionetteConfiguration())
      .findInteractiveElements();
  final refs = elements.map((e) => e['ref']).toList();
  expect(refs.first, '@1');
  expect(refs.length >= 2, isTrue);
  for (final e in elements) {
    expect(e.containsKey('ref'), isTrue);
  }
});
```

- [ ] **Step 2: Run test, verify failure (no `ref` key yet).**

Run: `cd packages/marionette_flutter && flutter test test/element_tree_finder_test.dart`
Expected: failure on the new test.

- [ ] **Step 3: Wire SnapshotSession into `findInteractiveElements`.**

Modify `element_tree_finder.dart`. At the top of `findInteractiveElements`:

```dart
import 'package:marionette_flutter/src/services/snapshot_session.dart';
import 'package:marionette_flutter/src/services/stable_identity.dart';

List<Map<String, dynamic>> findInteractiveElements({
  SnapshotOptions options = const SnapshotOptions(),
}) {
  SnapshotSession.instance.beginSnapshot();
  ...
}
```

In `_extractElementData`, after computing existing fields and before `return data;`, build identity and assign ref:

```dart
final identity = _buildIdentity(element, widget, discoverableText);
final ref = SnapshotSession.instance.assign(identity);
data['ref'] = ref;
```

Add helper:

```dart
StableIdentity _buildIdentity(Element element, Widget widget, String? text) {
  final ancestors = <String>[];
  element.visitAncestorElements((a) {
    final n = a.widget.runtimeType.toString();
    if (!n.startsWith('_') && ancestors.length < 5) ancestors.add(n);
    return true;
  });
  // siblingIndex among same-typed siblings under same parent
  int siblingIndex = 0;
  final parent = element.findAncestorWidgetOfExactType<Widget>() ;
  // Simpler: iterate parent's children
  // (parent retrieval omitted for brevity — implement via element.parent if exposed,
  // otherwise track index during walk via a per-parent counter.)
  return StableIdentity(
    key: widget.key,
    widgetType: widget.runtimeType.toString(),
    ancestorTypePath: ancestors,
    textFingerprint: text,
    siblingIndex: siblingIndex,
  );
}
```

For accurate `siblingIndex`, compute during the walk by tracking, per parent visited, a `Map<String, int>` of typename → next index. Refactor `_visitElement` to thread a parent counter map:

```dart
void _visitElement(
  Element element,
  List<Map<String, dynamic>> result, {
  Map<String, int>? siblingCounters,
  String? parentRef,
}) {
  final ownCounters = <String, int>{};
  // ... existing checks ...
  final widget = element.widget;
  final myType = widget.runtimeType.toString();
  final myIndex = (siblingCounters ?? const <String, int>{})[myType] ?? 0;
  if (siblingCounters != null) {
    siblingCounters[myType] = myIndex + 1;
  }
  final data = _extractElementData(element, widget, siblingIndex: myIndex);
  if (data != null) {
    if (parentRef != null) data['parentRef'] = parentRef;
    result.add(data);
  }
  final myRef = data?['ref'] as String?;
  if (configuration.shouldStopAtType(widget.runtimeType)) return;
  element.visitChildren((child) {
    _visitElement(child, result, siblingCounters: ownCounters, parentRef: myRef ?? parentRef);
  });
}
```

Update `_extractElementData` to accept `siblingIndex` and pass it to `_buildIdentity`.

- [ ] **Step 4: Run tests.**

Run: `cd packages/marionette_flutter && flutter test test/element_tree_finder_test.dart`
Expected: pass.

- [ ] **Step 5: Commit.**

```bash
git add packages/marionette_flutter/lib/src/services/element_tree_finder.dart \
        packages/marionette_flutter/test/element_tree_finder_test.dart
git commit -m "feat(marionette_flutter): assign refs and parentRef during interactive snapshot"
```

---

### Task 7: `compact` mode — strip debugFillProperties + extractProperties bulk

**Files:**
- Modify: `packages/marionette_flutter/lib/src/services/element_tree_finder.dart`
- Test: `packages/marionette_flutter/test/snapshot_options_test.dart` (extend)

- [ ] **Step 1: Write failing test.**

```dart
testWidgets('compact: true drops debugFillProperties keys, keeps allow-list', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Switch(value: true, onChanged: (_) {}),
    ),
  ));
  final finder = ElementTreeFinder(const MarionetteConfiguration());
  final compact = finder.findInteractiveElements(
    options: const SnapshotOptions(compact: true),
  );
  final entry = compact.firstWhere((e) => e['type'] == 'Switch');
  // Allow-list keys retained:
  expect(entry.containsKey('value'), isTrue);
  // Bulk debugFillProperties keys dropped (e.g. 'activeColor'):
  expect(entry.containsKey('activeColor'), isFalse);
});
```

- [ ] **Step 2: Verify failure.**

Run: `cd packages/marionette_flutter && flutter test test/snapshot_options_test.dart`
Expected: failure.

- [ ] **Step 3: Implement.**

In `_extractElementData`, after building the `data` map but before returning:

```dart
const _compactAllowList = {'enabled', 'value', 'selected', 'checked'};

if (options.compact) {
  data.removeWhere((k, _) => !_compactCoreKeys.contains(k) && !_compactAllowList.contains(k));
}
```

Where `_compactCoreKeys = {'type','text','key','bounds','visible','ref','parentRef'}`.

Pass `options` through to `_extractElementData` and `_visitElement`.

- [ ] **Step 4: Run tests.**

Run: `cd packages/marionette_flutter && flutter test`
Expected: pass.

- [ ] **Step 5: Commit.**

```bash
git add packages/marionette_flutter/lib/src/services/element_tree_finder.dart \
        packages/marionette_flutter/test/snapshot_options_test.dart
git commit -m "feat(marionette_flutter): compact mode strips debugFillProperties bulk"
```

---

### Task 8: `prune` mode — Offstage / non-current-route / zero-size

**Files:**
- Modify: `packages/marionette_flutter/lib/src/services/element_tree_finder.dart`
- Test: `packages/marionette_flutter/test/snapshot_options_test.dart` (extend)

- [ ] **Step 1: Write failing test.**

```dart
testWidgets('prune skips Offstage subtrees', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Column(children: [
        ElevatedButton(onPressed: () {}, child: const Text('Visible')),
        const Offstage(
          offstage: true,
          child: Material(child: TextButton(onPressed: null, child: Text('Hidden'))),
        ),
      ]),
    ),
  ));
  final finder = ElementTreeFinder(const MarionetteConfiguration());
  final pruned = finder.findInteractiveElements(
    options: const SnapshotOptions(prune: true),
  );
  expect(pruned.any((e) => e['text'] == 'Hidden'), isFalse);
  expect(pruned.any((e) => e['text'] == 'Visible'), isTrue);
});
```

- [ ] **Step 2: Verify failure.**

Run as above.

- [ ] **Step 3: Implement Offstage skip in `_visitElement`.**

```dart
if (options.prune && widget is Offstage && widget.offstage) {
  return;
}
```

Implement zero-size skip:

```dart
final ro = element.renderObject;
if (options.prune && ro is RenderBox && ro.hasSize && ro.size.isEmpty) {
  return;
}
```

Implement non-current-route skip. Track a `ModalRoute?` while walking; pass through recursion:

```dart
if (options.prune && element is StatefulElement) {
  final route = ModalRoute.of(element);
  if (route != null && route != activeRouteContext) {
    if (!route.isCurrent) return;
    activeRouteContext = route;
  }
}
```

Add corresponding tests for non-current-route (push a dialog, snapshot, assert underlying screen widgets absent) and zero-size in the same file. Implement and verify.

- [ ] **Step 4: Run tests.**

Expected: pass.

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette_flutter): prune Offstage / non-current-route / zero-size in snapshot"
```

---

### Task 9: `limit` and `truncated`

**Files:**
- Modify: `packages/marionette_flutter/lib/src/services/element_tree_finder.dart`
- Test: `packages/marionette_flutter/test/snapshot_options_test.dart`

- [ ] **Step 1: Failing test.**

```dart
testWidgets('limit caps result and surfaces truncated:true', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Column(
        children: List.generate(
          10,
          (i) => ElevatedButton(onPressed: () {}, child: Text('B$i')),
        ),
      ),
    ),
  ));
  final finder = ElementTreeFinder(const MarionetteConfiguration());
  final result = finder.findInteractiveElementsWithMeta(
    options: const SnapshotOptions(limit: 5),
  );
  expect(result.elements.length, 5);
  expect(result.truncated, isTrue);
});
```

This requires a new wrapper return type since today's signature returns a bare list. Introduce `SnapshotResult` and a parallel method:

```dart
class SnapshotResult {
  SnapshotResult({required this.elements, this.truncated = false, this.screenName, this.routeName});
  final List<Map<String, dynamic>> elements;
  final bool truncated;
  final String? screenName;
  final String? routeName;
}
```

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Implement.**

Add `findInteractiveElementsWithMeta` that wraps the walk, tracking a counter; when count == limit, set `truncated = true` and stop. Refactor `findInteractiveElements` to delegate to it (`.elements`).

- [ ] **Step 4: Run tests.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette_flutter): limit + truncated in snapshot"
```

---

### Task 10: `viewportOnly`

**Files:**
- Modify: `packages/marionette_flutter/lib/src/services/element_tree_finder.dart`
- Test: extend `snapshot_options_test.dart`

- [ ] **Step 1: Failing test** — pump a tall list; assert default returns offscreen items, `viewportOnly: true` excludes them.

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Implement.** In `_extractElementData`, when `options.viewportOnly`, compute screen rect (`view.physicalSize / view.devicePixelRatio`) and return null when bounds don't intersect.

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette_flutter): viewportOnly snapshot option"
```

---

### Task 11: `scope` — root snapshot at ref or selector

**Files:**
- Modify: `packages/marionette_flutter/lib/src/services/element_tree_finder.dart`

- [ ] **Step 1: Failing test** — set up a tree with two cards; describe with `scope: '@2'`, assert only descendants of @2 returned. Also test `scope: 'key:dialog'`.

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Implement.** When `scope` looks like `@N`, look up identity via session, walk to find element, root walk there. When it's a selector string (`key:foo`, `text:Bar`), build a `WidgetMatcher` and find the root that way. Note: `scope` requires a prior snapshot for ref form.

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette_flutter): scope snapshot to subtree by ref or selector"
```

---

### Task 12: Tooltip ancestor inheritance

**Files:**
- Modify: `packages/marionette_flutter/lib/src/services/element_tree_finder.dart`

- [ ] **Step 1: Failing test** — IconButton inside Tooltip(message: 'Save'); snapshot entry's `text` == 'Save'.

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Implement.** Track `currentTooltip` while walking. When entering a Tooltip widget, capture `widget.message`; when leaving, restore. In `_extractElementData`, if `text` is null and `currentTooltip != null`, use the tooltip.

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette_flutter): tooltip-as-label fallback in snapshot"
```

---

### Task 13: `screenName` and `routeName` extraction

**Files:**
- Modify: `packages/marionette_flutter/lib/src/services/element_tree_finder.dart`

- [ ] **Step 1: Failing test** — pump a Scaffold with AppBar(title: Text('Home')); assert `screenName == 'Home'` in `SnapshotResult`. Push a named route, assert `routeName`.

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Implement.** During walk, when entering Scaffold, scan for AppBar/SliverAppBar title text; record once. When entering a current ModalRoute, capture `route.settings.name`.

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette_flutter): include screenName and routeName in snapshot result"
```

---

### Task 14: Wire `SnapshotOptions` through the VM service extension

**Files:**
- Modify: `packages/marionette_flutter/lib/src/binding/extensions/info_extensions.dart`
- Test: `packages/marionette_flutter/test/info_extensions_test.dart` (new)

- [ ] **Step 1: Failing test.**

```dart
// Verifies that calling marionette.interactiveElements with new params
// yields the expected reshaped output. Use a TestWidgetsFlutterBinding
// to drive ServiceExtensionResponse pathway directly.
```

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Replace the body of the `marionette.interactiveElements` registration:**

```dart
registerInternalMarionetteExtension(
  name: 'marionette.interactiveElements',
  callback: (params) async {
    final options = SnapshotOptions.fromJson(params);
    final result = elementTreeFinder.findInteractiveElementsWithMeta(options: options);
    return MarionetteExtensionResult.success({
      'elements': result.elements,
      if (result.truncated) 'truncated': true,
      if (result.screenName != null) 'screenName': result.screenName,
      if (result.routeName != null) 'routeName': result.routeName,
    });
  },
);
```

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette_flutter): plumb SnapshotOptions through VM service ext"
```

---

### Task 15: `RefMatcher` in `widget_matcher.dart`

**Files:**
- Modify: `packages/marionette_flutter/lib/src/services/widget_matcher.dart`
- Test: `packages/marionette_flutter/test/ref_matcher_test.dart`

- [ ] **Step 1: Failing test.**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/services/snapshot_session.dart';
import 'package:marionette_flutter/src/services/stable_identity.dart';

void main() {
  setUp(() => SnapshotSession.instance.reset());

  test('WidgetMatcher.fromJson returns RefMatcher for ref param', () {
    final m = WidgetMatcher.fromJson({'ref': '@5'});
    expect(m, isA<RefMatcher>());
    expect((m as RefMatcher).ref, '@5');
  });

  test('RefMatcher matches element whose identity matches stored', () {
    SnapshotSession.instance.beginSnapshot();
    const id = StableIdentity(
      key: ValueKey('save'),
      widgetType: 'ElevatedButton',
      ancestorTypePath: [],
      textFingerprint: null,
      siblingIndex: 0,
    );
    final ref = SnapshotSession.instance.assign(id);
    final m = WidgetMatcher.fromJson({'ref': ref}) as RefMatcher;
    // Construct a fake element-like check: matchesIdentity should be true
    expect(SnapshotSession.instance.lookup(ref)!.matchesIdentity(id), isTrue);
    expect(m, isNotNull);
  });
}
```

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Implement.**

Add to `WidgetMatcher.fromJson` selector chain (highest precedence after focused/coordinates, before key):

```dart
} else if (json.containsKey('ref')) {
  return RefMatcher.fromJson(json);
```

Add the class:

```dart
class RefMatcher extends WidgetMatcher {
  const RefMatcher(this.ref);
  final String ref;

  factory RefMatcher.fromJson(Map<String, dynamic> json) =>
      RefMatcher(json['ref'] as String);

  @override
  bool matches(Element element, MarionetteConfiguration configuration) {
    final stored = SnapshotSession.instance.lookup(ref);
    if (stored == null) return false;
    final candidate = _identityFor(element, configuration);
    return stored.matchesIdentity(candidate);
  }

  StableIdentity _identityFor(Element element, MarionetteConfiguration cfg) {
    // Build the same identity shape used during snapshot — share a helper
    // with element_tree_finder.dart by exporting `buildIdentityFor(element)`
    // from a common location.
  }

  @override
  Map<String, dynamic> toJson() => {'ref': ref};
}
```

Refactor: extract `buildIdentityFor(Element, MarionetteConfiguration)` from `element_tree_finder.dart` into `stable_identity.dart` so both call sites share it. The `siblingIndex` cannot be reconstructed without parent context; store enough on `RefMatcher` resolution to walk siblings of same type and use position.

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit.**

```bash
git add packages/marionette_flutter/lib/src/services/widget_matcher.dart \
        packages/marionette_flutter/test/ref_matcher_test.dart \
        packages/marionette_flutter/lib/src/services/stable_identity.dart \
        packages/marionette_flutter/lib/src/services/element_tree_finder.dart
git commit -m "feat(marionette_flutter): RefMatcher resolves @N via SnapshotSession"
```

---

### Task 16: Action error codes (`ref-unknown`/`ref-stale`/`ref-ambiguous`)

**Files:**
- Modify: `packages/marionette_flutter/lib/src/services/widget_finder.dart`
- Test: `packages/marionette_flutter/test/ref_matcher_test.dart` (extend)

- [ ] **Step 1: Failing test** — Verify `findHittableElement(RefMatcher('@99'), ...)` returns a result indicating "ref-unknown" (e.g., a sentinel result type or specific exception).

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Refactor `findHittableElement` to return a result with an error code:**

```dart
sealed class FindResult {
  const FindResult();
}
class FoundElement extends FindResult {
  FoundElement(this.element);
  final Element element;
}
class FindError extends FindResult {
  FindError(this.code);
  final String code; // 'not-found', 'ref-unknown', 'ref-stale', 'ref-ambiguous'
}
```

For `RefMatcher`:
- If `SnapshotSession.lookup(ref)` returns null → `FindError('ref-unknown')`.
- Walk tree, count matches. Zero → `FindError('ref-stale')`. Multiple → `FindError('ref-ambiguous')`. One → `FoundElement(...)`.

Update existing call sites of `findHittableElement` to handle the new return type; existing matcher behavior continues to use a generic `'not-found'` error.

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette_flutter): structured FindResult with ref-specific error codes"
```

---

### Task 17: Auto-rescroll-into-view + `ensureVisible` opt-out

**Files:**
- Modify: `packages/marionette_flutter/lib/src/services/gesture_dispatcher.dart`
- Test: `packages/marionette_flutter/test/auto_ensure_visible_test.dart`

- [ ] **Step 1: Failing test** — pump a tall ListView; describe (refs assigned for offscreen items); attempt to tap an offscreen ref; assert it succeeds without manual scroll. Also test `ensureVisible: false` errors with `ref-unreachable`.

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Implement.**

In `gesture_dispatcher.dart`, add a `_ensureVisibleIfNeeded(matcher, finder, configuration, ensureVisible)` helper. When matcher is `RefMatcher` and the candidate isn't currently hittable but exists:
1. Find the element via `findElement` (non-hittable variant).
2. Walk ancestors for nearest `Scrollable`; call `Scrollable.ensureVisible(element, duration: zero)`.
3. `await SchedulerBinding.instance.endOfFrame`.
4. Re-find with `findHittableElement`. If still not hittable → return `FindError('ref-unreachable')`.

Wire this helper into `tap`, `doubleTap`, `longPress`, `enterText`, `swipe`, `scrollTo`, `pinchZoom`. All accept a new `bool ensureVisible = true` parameter.

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette_flutter): auto-ensureVisible for ref-based actions"
```

---

### Task 18: Wire `ensureVisible` through gesture extensions

**Files:**
- Modify: `packages/marionette_flutter/lib/src/binding/extensions/gesture_extensions.dart`

- [ ] **Step 1: Failing test** — call the `marionette.tap` extension with `params: {'ref': '@1', 'ensureVisible': 'false'}` against an offscreen widget; assert response is `ref-unreachable`.

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Implement.** In each extension callback:

```dart
final ensureVisible = params['ensureVisible'] != 'false';
final matcher = WidgetMatcher.fromJson(params);
final result = await gestureDispatcher.tap(
  matcher, widgetFinder, configuration, ensureVisible: ensureVisible,
);
return result.toExtensionResult();
```

Where `result.toExtensionResult()` maps `FoundElement` to success and `FindError(code)` to `MarionetteExtensionResult.error(...)` with the code string.

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette_flutter): pass ensureVisible through gesture extensions"
```

---

### Task 19: MCP — accept new params on `get_interactive_elements`

**Files:**
- Modify: `packages/marionette_mcp/lib/src/vm_service/tools/inspection_tools.dart`

- [ ] **Step 1: Read current schema; add new optional params.**

- [ ] **Step 2: Update schema.**

```dart
inputSchema: {
  'type': 'object',
  'properties': {
    'compact': {'type': 'boolean', 'description': 'Strip debugFillProperties...'},
    'prune': {'type': 'boolean', 'description': '...'},
    'limit': {'type': 'integer'},
    'viewportOnly': {'type': 'boolean'},
    'scope': {'type': 'string', 'description': 'Ref like "@5" or selector'},
  },
},
```

- [ ] **Step 3: Forward params to the VM service ext call.**

- [ ] **Step 4: Run package tests.**

```bash
cd packages/marionette_mcp && dart test
```

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette_mcp): expose snapshot options on get_interactive_elements"
```

---

### Task 20: MCP — add `ref` selector to action tools

**Files:**
- Modify: `packages/marionette_mcp/lib/src/vm_service/tools/gesture_tools.dart`

- [ ] **Step 1: Test** — call MCP `tap` tool with `{ref: '@5'}`; assert it forwards correctly.

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Update each gesture tool's input schema with `ref` as a `oneOf` selector option, and add optional `ensureVisible` boolean.**

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette_mcp): ref selector + ensureVisible on gesture tools"
```

---

### Task 21: CLI — `get_interactive_elements` flags

**Files:**
- Modify: `packages/marionette_cli/lib/src/cli/commands/get_interactive_elements_command.dart`

- [ ] **Step 1: Test** — run command with `--compact --prune --limit 10`, assert params propagate.

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Add flags to `argParser`:**

```dart
argParser
  ..addFlag('compact', help: 'Strip debugFillProperties bulk; use allow-list')
  ..addFlag('prune', help: 'Skip Offstage / non-current-route / zero-size')
  ..addOption('limit', help: 'Cap on entries; sets truncated:true if hit')
  ..addFlag('viewport-only', help: 'Only entries intersecting screen')
  ..addOption('scope', help: 'Ref (@N) or selector to root snapshot');
```

Pass through to extension call.

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette_cli): snapshot-option flags on get-interactive-elements"
```

---

### Task 22: CLI — `--ref` and `--no-ensure-visible` on action commands

**Files:**
- Modify: `packages/marionette_cli/lib/src/cli/commands/<each action>_command.dart`

- [ ] **Step 1: Test** — `marionette tap --ref @5` calls extension with `{ref: '@5'}`.

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: For each of `tap`, `double_tap`, `long_press`, `enter_text`, `scroll_to`, `swipe`:**

Add to `argParser`:

```dart
..addOption('ref', help: 'Reference @N from a prior get-interactive-elements')
..addFlag('ensure-visible', defaultsTo: true, negatable: true, help: '...')
```

Pass into the extension param map.

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette_cli): --ref and --no-ensure-visible on action commands"
```

---

### Task 23: Integration — ref chain across separate ext calls

**Files:**
- Test: `packages/marionette_flutter/test/integration/ref_chain_test.dart` (new)

- [ ] **Step 1: Write integration test.**

```dart
testWidgets('describe → tap @N → enter_text @M chain', (tester) async {
  // pump a form with a TextField and a Save button
  // call findInteractiveElementsWithMeta to populate session
  // grab refs by text (e.g. find @ for 'Save')
  // dispatch tap via gestureDispatcher with RefMatcher
  // verify tap fired
});
```

- [ ] **Step 2: Verify failure (if it fails).**

- [ ] **Step 3: Fix any plumbing issues exposed by the integration test.**

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "test(marionette_flutter): integration test for ref-based action chaining"
```

---

### Task 24: CHANGELOG + docs

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `packages/marionette_flutter/CHANGELOG.md`
- Modify: `packages/marionette_mcp/CHANGELOG.md`
- Modify: `README.md` (snippet about refs and chaining)

- [ ] **Step 1: Add entries describing additive params, new fields (ref, parentRef, screenName, routeName, truncated), expanded built-in list, tooltip-as-label fallback note.**

- [ ] **Step 2: Verify by reading.**

- [ ] **Step 3: Commit.**

```bash
git commit -am "docs: changelog and readme updates for refs/snapshot tightening"
```

---

### Task 25: Final verification

- [ ] **Step 1: Run full test suite across all packages.**

```bash
for d in packages/*/; do (cd "$d" && (dart test || flutter test) 2>&1 | tail -10); done
```

Expected: green across the board.

- [ ] **Step 2: Run analyze across all packages.**

```bash
dart analyze
```

Expected: no issues.

- [ ] **Step 3: Verify spec coverage by reading the spec and matching each requirement to a task above.**

- [ ] **Step 4: Push the branch.**

```bash
git push -u origin feat/describe-refs
```

- [ ] **Step 5: Open a PR if requested.**

---

## Self-Review Notes

- **Spec coverage:** every spec section maps to a task — refs (T6/T15), parentRef (T6), screenName/routeName (T13), built-in list (T4), tooltip (T12), compact (T7), prune (T8), limit/truncated (T9), viewportOnly (T10), scope (T11), action ref (T15), auto-ensure-visible (T17), error codes (T16), MCP/CLI surfaces (T19–22), integration (T23).
- **Gaps:** the open question about loopback/ref-via-selector parity in `scope` is explicitly handled in Task 11. Persistence across snapshots is intentionally not supported; tests in T15/T16 confirm cross-call resolution works because the session is in-app.
- **Type consistency:** `SnapshotResult.elements` / `SnapshotOptions.compact` / `RefMatcher.ref` — names used consistently.
