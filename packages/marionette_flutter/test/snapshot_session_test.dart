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
