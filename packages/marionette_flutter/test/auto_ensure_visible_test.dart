import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/services/element_tree_finder.dart';
import 'package:marionette_flutter/src/services/gesture_dispatcher.dart';
import 'package:marionette_flutter/src/services/snapshot_session.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';

void main() {
  setUp(() => SnapshotSession.instance.reset());

  group('Auto ensureVisible', () {
    testWidgets('tap returns FoundElement for visible ref', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const ValueKey('btn'),
              onPressed: () {},
              child: const Text('Tap me'),
            ),
          ),
        ),
      ));

      final finder = ElementTreeFinder(const MarionetteConfiguration());
      final elements = finder.findInteractiveElements();
      final ref = elements.firstWhere((e) => e['key'] == 'btn')['ref'] as String;

      final dispatcher = GestureDispatcher();
      final result = await tester.runAsync(() => dispatcher.tap(
        RefMatcher(ref),
        WidgetFinder(),
        const MarionetteConfiguration(),
      ));

      expect(result, isA<FoundElement>());
    });

    testWidgets('tap returns ref-unknown for non-existent ref', (tester) async {
      SnapshotSession.instance.reset();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Hello')),
        ),
      ));

      final dispatcher = GestureDispatcher();
      final result = await tester.runAsync(() => dispatcher.tap(
        const RefMatcher('@99'),
        WidgetFinder(),
        const MarionetteConfiguration(),
      ));

      expect(result, isA<FindError>());
      expect((result as FindError).code, 'ref-unknown');
    });
  });
}
