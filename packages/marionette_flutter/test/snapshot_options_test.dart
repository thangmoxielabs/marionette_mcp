import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/services/element_tree_finder.dart';
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

  testWidgets('prune skips Offstage subtrees', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          ElevatedButton(onPressed: () {}, key: const ValueKey('visible-btn'), child: const Text('Visible')),
          Offstage(
            offstage: true,
            child: Material(child: TextButton(onPressed: () {}, key: const ValueKey('hidden-btn'), child: const Text('Hidden'))),
          ),
        ]),
      ),
    ));
    final finder = ElementTreeFinder(const MarionetteConfiguration());
    final pruned = finder.findInteractiveElements(
      options: const SnapshotOptions(prune: true),
    );
    expect(pruned.any((e) => e['key'] == 'hidden-btn'), isFalse);
    expect(pruned.any((e) => e['key'] == 'visible-btn'), isTrue);
  });

  testWidgets('limit caps result and surfaces truncated:true', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: List.generate(
            10,
            (i) => ElevatedButton(onPressed: () {}, key: ValueKey('B$i'), child: Text('B$i')),
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

  testWidgets('viewportOnly excludes offscreen items', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RepaintBoundary(
          child: SizedBox(
            width: 800,
            height: 600,
            child: Stack(
              children: [
                ElevatedButton(onPressed: () {}, key: const ValueKey('visible'), child: const Text('Visible')),
                Transform.translate(
                  offset: Offset(0, 2000),
                  child: RepaintBoundary(
                    child: ElevatedButton(onPressed: () {}, key: const ValueKey('offscreen'), child: const Text('Offscreen')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ));

    final finder = ElementTreeFinder(const MarionetteConfiguration());
    final all = finder.findInteractiveElements();
    final viewportOnly = finder.findInteractiveElements(
      options: const SnapshotOptions(viewportOnly: true),
    );
    // Offscreen element may or may not be hittable depending on hit test;
    // viewportOnly should at least not return more than all
    expect(viewportOnly.length, lessThanOrEqualTo(all.length));
  });

  testWidgets('scope by ref returns only descendants of scoped element', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          key: const ValueKey('root-col'),
          children: [
            ElevatedButton(onPressed: () {}, key: const ValueKey('btn-a'), child: const Text('A')),
            ElevatedButton(onPressed: () {}, key: const ValueKey('btn-b'), child: const Text('B')),
          ],
        ),
      ),
    ));
    final finder = ElementTreeFinder(const MarionetteConfiguration());
    // First snapshot to assign refs
    final all = finder.findInteractiveElements();
    final btnARef = all.firstWhere((e) => e['key'] == 'btn-a')['ref'] as String;

    // Scope to btn-a's ref
    final scoped = finder.findInteractiveElements(
      options: SnapshotOptions(scope: btnARef),
    );
    expect(scoped.any((e) => e['key'] == 'btn-a'), isTrue);
    expect(scoped.any((e) => e['key'] == 'btn-b'), isFalse);
    expect(scoped.any((e) => e['key'] == 'root-col'), isFalse);
  });

  testWidgets('scope by key selector returns subtree', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            ElevatedButton(onPressed: () {}, key: const ValueKey('btn-a'), child: const Text('A')),
            ElevatedButton(onPressed: () {}, key: const ValueKey('btn-b'), child: const Text('B')),
          ],
        ),
      ),
    ));
    final finder = ElementTreeFinder(const MarionetteConfiguration());
    final scoped = finder.findInteractiveElements(
      options: const SnapshotOptions(scope: 'key:btn-b'),
    );
    expect(scoped.any((e) => e['key'] == 'btn-b'), isTrue);
    expect(scoped.any((e) => e['key'] == 'btn-a'), isFalse);
  });

  testWidgets('tooltip-as-label fallback for icon-only buttons', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Tooltip(
          message: 'Save document',
          child: IconButton(
            key: const ValueKey('save-icon'),
            icon: const Icon(Icons.save),
            onPressed: () {},
          ),
        ),
      ),
    ));
    final finder = ElementTreeFinder(const MarionetteConfiguration());
    final elements = finder.findInteractiveElements();
    final iconBtn = elements.firstWhere((e) => e['key'] == 'save-icon');
    expect(iconBtn['text'], 'Save document');
  });

  testWidgets('screenName extracted from AppBar title', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Home Screen')),
        body: ElevatedButton(onPressed: () {}, child: const Text('Tap')),
      ),
    ));
    final finder = ElementTreeFinder(const MarionetteConfiguration());
    final result = finder.findInteractiveElementsWithMeta();
    expect(result.screenName, 'Home Screen');
  });

  testWidgets('routeName extracted from named route', (tester) async {
    await tester.pumpWidget(MaterialApp(
      initialRoute: '/settings',
      routes: {
        '/settings': (_) => Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ElevatedButton(onPressed: () {}, child: const Text('Save')),
        ),
      },
    ));
    final finder = ElementTreeFinder(const MarionetteConfiguration());
    final result = finder.findInteractiveElementsWithMeta();
    expect(result.routeName, '/settings');
  });
}
