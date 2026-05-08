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
