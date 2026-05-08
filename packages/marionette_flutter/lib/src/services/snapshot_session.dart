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
