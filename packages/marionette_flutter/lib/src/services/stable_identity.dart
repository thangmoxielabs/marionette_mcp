import 'package:flutter/foundation.dart';

/// Identifies a widget across rebuilds without holding an Element reference.
///
/// When [key] is non-null, identity matching uses key alone.
/// Otherwise it uses the tuple (widgetType, ancestorTypePath, textFingerprint,
/// siblingIndex among same-typed siblings under the same parent).
@immutable
class StableIdentity {
  const StableIdentity({
    required this.key,
    required this.widgetType,
    required this.ancestorTypePath,
    required this.textFingerprint,
    required this.siblingIndex,
  });

  final Key? key;
  final String widgetType;
  final List<String> ancestorTypePath;
  final String? textFingerprint;
  final int siblingIndex;

  bool matchesIdentity(StableIdentity other) {
    if (key != null && other.key != null) {
      return key == other.key;
    }
    if (key != null || other.key != null) {
      return false;
    }
    return widgetType == other.widgetType &&
        listEquals(ancestorTypePath, other.ancestorTypePath) &&
        textFingerprint == other.textFingerprint &&
        siblingIndex == other.siblingIndex;
  }
}
