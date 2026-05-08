import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/services/element_tree_finder.dart';
import 'package:marionette_flutter/src/services/snapshot_session.dart';
import 'package:marionette_flutter/src/services/stable_identity.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';
import 'package:marionette_flutter/src/services/widget_matcher.dart';
import 'package:test/test.dart' as dart_test;

void main() {
  group('WidgetMatcher.fromJson', () {
    dart_test.test('returns FocusedElementMatcher for focused matcher', () {
      final matcher = WidgetMatcher.fromJson({'focused': true});

      dart_test.expect(matcher, isA<FocusedElementMatcher>());
    });

    dart_test.test('focused matcher has highest precedence', () {
      final matcher = WidgetMatcher.fromJson({
        'focused': true,
        'key': 'name_field',
      });

      dart_test.expect(matcher, isA<FocusedElementMatcher>());
    });

    dart_test.test('returns RefMatcher for ref param', () {
      final m = WidgetMatcher.fromJson({'ref': '@5'});
      dart_test.expect(m, isA<RefMatcher>());
      dart_test.expect((m as RefMatcher).ref, '@5');
    });

    dart_test.test('RefMatcher matches element whose identity matches stored', () {
      SnapshotSession.instance.reset();
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
      dart_test.expect(SnapshotSession.instance.lookup(ref)!.matchesIdentity(id), isTrue);
      dart_test.expect(m, isNotNull);
    });
  });

  group('FocusedElementMatcher', () {
    dart_test.test('serializes to focused json', () {
      const matcher = FocusedElementMatcher();

      dart_test.expect(matcher.toJson(), {'focused': true});
    });
  });

  group('RefMatcher', () {
    setUp(() => SnapshotSession.instance.reset());

    dart_test.test('toJson returns ref', () {
      const m = RefMatcher('@3');
      dart_test.expect(m.toJson(), {'ref': '@3'});
    });

    dart_test.test('returns false for unknown ref', () {
      const m = RefMatcher('@99');
      // Unknown ref should return false without needing a real element
      final stored = SnapshotSession.instance.lookup('@99');
      dart_test.expect(stored, isNull);
    });
  });

  group('FindResult', () {
    setUp(() => SnapshotSession.instance.reset());

    testWidgets('findHittableElement returns FoundElement for valid ref', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ElevatedButton(onPressed: () {}, key: const ValueKey('save'), child: const Text('Save')),
        ),
      ));
      // First snapshot to assign refs
      final finder = ElementTreeFinder(const MarionetteConfiguration());
      final elements = finder.findInteractiveElements();
      final ref = elements.firstWhere((e) => e['key'] == 'save')['ref'] as String;

      final widgetFinder = WidgetFinder();
      final result = widgetFinder.findHittableElement(
        RefMatcher(ref),
        const MarionetteConfiguration(),
      );
      dart_test.expect(result, isA<FoundElement>());
    });

    testWidgets('findHittableElement returns ref-unknown for missing ref', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ElevatedButton(onPressed: () {}, child: const Text('Save')),
        ),
      ));
      final widgetFinder = WidgetFinder();
      final result = widgetFinder.findHittableElement(
        const RefMatcher('@99'),
        const MarionetteConfiguration(),
      );
      dart_test.expect(result, isA<FindError>());
      dart_test.expect((result as FindError).code, 'ref-unknown');
    });

    testWidgets('findHittableElement returns ref-stale for no match', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ElevatedButton(onPressed: () {}, key: const ValueKey('save'), child: const Text('Save')),
        ),
      ));
      // Assign a ref but then pump a different widget tree
      final finder = ElementTreeFinder(const MarionetteConfiguration());
      finder.findInteractiveElements();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ElevatedButton(onPressed: () {}, key: const ValueKey('other'), child: const Text('Other')),
        ),
      ));

      final widgetFinder = WidgetFinder();
      final result = widgetFinder.findHittableElement(
        const RefMatcher('@1'),
        const MarionetteConfiguration(),
      );
      dart_test.expect(result, isA<FindError>());
      dart_test.expect((result as FindError).code, 'ref-stale');
    });
  });
}
