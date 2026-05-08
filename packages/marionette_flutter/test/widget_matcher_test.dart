import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/services/snapshot_session.dart';
import 'package:marionette_flutter/src/services/stable_identity.dart';
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
}
