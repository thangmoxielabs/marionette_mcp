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
}
