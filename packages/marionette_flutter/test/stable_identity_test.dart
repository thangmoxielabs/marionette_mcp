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
