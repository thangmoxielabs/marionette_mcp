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
