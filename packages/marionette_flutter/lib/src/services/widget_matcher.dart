import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/services/snapshot_session.dart';
import 'package:marionette_flutter/src/services/stable_identity.dart';

/// Abstract base class for matching widgets in the Flutter widget tree.
sealed class WidgetMatcher {
  const WidgetMatcher();

  /// Checks if the given [element] matches this matcher's criteria.
  bool matches(Element element, MarionetteConfiguration configuration);

  /// Creates a matcher from a JSON map.
  /// If multiple fields are present, precedence is:
  /// 'focused' > coordinates (x & y) > 'key' > 'text' > 'type'.
  static WidgetMatcher fromJson(Map<String, dynamic> json) {
    // Focused matcher has highest precedence because it bypasses tree search.
    if (json.containsKey('focused')) {
      return const FocusedElementMatcher();
    } else if (json.containsKey('x') && json.containsKey('y')) {
      return CoordinatesMatcher.fromJson(json);
    } else if (json.containsKey('key')) {
      return KeyMatcher.fromJson(json);
    } else if (json.containsKey('text')) {
      return TextMatcher.fromJson(json);
    } else if (json.containsKey('type')) {
      return TypeStringMatcher.fromJson(json);
    } else if (json.containsKey('ref')) {
      return RefMatcher.fromJson(json);
    } else {
      throw ArgumentError(
        'Matcher JSON must contain "focused", "x" & "y", "key", "text", "type", or "ref" field',
      );
    }
  }

  /// Converts this matcher to a JSON-serializable map.
  Map<String, dynamic> toJson();
}

/// Matches the currently focused element.
///
/// This matcher is not used for widget tree traversal and is handled as a
/// special case by [TextInputSimulator].
class FocusedElementMatcher extends WidgetMatcher {
  const FocusedElementMatcher();

  @override
  bool matches(Element element, MarionetteConfiguration configuration) {
    return false;
  }

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{'focused': true};
  }
}

/// Matches by screen coordinates. This is a special matcher that doesn't
/// actually match widgets - it's used as a fast path for tapping at
/// specific screen positions without searching the widget tree.
class CoordinatesMatcher extends WidgetMatcher {
  const CoordinatesMatcher(this.x, this.y);

  factory CoordinatesMatcher.fromJson(Map<String, dynamic> json) {
    final x = double.tryParse(json['x'].toString());
    final y = double.tryParse(json['y'].toString());
    if (x == null || y == null) {
      throw ArgumentError(
        'Coordinates "x" and "y" must be valid numbers, '
        'got x=${json['x']}, y=${json['y']}',
      );
    }
    return CoordinatesMatcher(x, y);
  }

  final double x;
  final double y;

  Offset get offset => Offset(x, y);

  @override
  bool matches(Element element, MarionetteConfiguration configuration) {
    // CoordinatesMatcher doesn't match widgets - it's handled specially
    // in GestureDispatcher.tap() as a fast path.
    return false;
  }

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{'x': x, 'y': y};
  }
}

/// Matches widgets by their `ValueKey<String>` key.
class KeyMatcher extends WidgetMatcher {
  const KeyMatcher(this.keyValue);

  factory KeyMatcher.fromJson(Map<String, dynamic> json) {
    return KeyMatcher(json['key'] as String);
  }

  final String keyValue;

  @override
  bool matches(Element element, MarionetteConfiguration configuration) {
    final key = element.widget.key;
    if (key is ValueKey<String>) {
      return key.value == keyValue;
    }
    return false;
  }

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{'key': keyValue};
  }
}

/// Matches widgets by their text content.
class TextMatcher extends WidgetMatcher {
  const TextMatcher(this.text);

  factory TextMatcher.fromJson(Map<String, dynamic> json) {
    return TextMatcher(json['text'] as String);
  }

  final String text;

  @override
  bool matches(Element element, MarionetteConfiguration configuration) {
    final extractedText = configuration.extractTextFromWidget(element);
    return extractedText == text;
  }

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{'text': text};
  }
}

/// Matches widgets by their runtime type.
class TypeMatcher extends WidgetMatcher {
  const TypeMatcher(this.type);

  final Type type;

  @override
  bool matches(Element element, MarionetteConfiguration configuration) {
    return element.widget.runtimeType == type;
  }

  @override
  Map<String, dynamic> toJson() {
    throw UnsupportedError('TypeMatcher does not support JSON serialization');
  }
}

/// Matches widgets by their runtime type as a string.
class TypeStringMatcher extends WidgetMatcher {
  const TypeStringMatcher(this.typeName);

  factory TypeStringMatcher.fromJson(Map<String, dynamic> json) {
    return TypeStringMatcher(json['type'] as String);
  }

  final String typeName;

  @override
  bool matches(Element element, MarionetteConfiguration configuration) {
    return element.widget.runtimeType.toString() == typeName;
  }

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{'type': typeName};
  }
}

/// Matches widgets by their ref from a prior snapshot.
///
/// Resolves the ref via [SnapshotSession] and compares the stored
/// [StableIdentity] against the candidate element's identity.
class RefMatcher extends WidgetMatcher {
  const RefMatcher(this.ref);

  factory RefMatcher.fromJson(Map<String, dynamic> json) =>
      RefMatcher(json['ref'] as String);

  final String ref;

  @override
  bool matches(Element element, MarionetteConfiguration configuration) {
    final stored = SnapshotSession.instance.lookup(ref);
    if (stored == null) return false;
    final text = configuration.extractTextFromWidget(element);
    final candidate = buildIdentityFor(element, element.widget, text, 0);
    return stored.matchesIdentity(candidate);
  }

  @override
  Map<String, dynamic> toJson() => {'ref': ref};
}

/// Builds a [StableIdentity] for an element. Shared between the snapshot walker
/// and [RefMatcher].
StableIdentity buildIdentityFor(Element element, Widget widget, String? text, int siblingIndex) {
  final ancestors = <String>[];
  element.visitAncestorElements((a) {
    final n = a.widget.runtimeType.toString();
    if (!n.startsWith('_') && ancestors.length < 5) ancestors.add(n);
    return true;
  });
  return StableIdentity(
    key: widget.key,
    widgetType: widget.runtimeType.toString(),
    ancestorTypePath: ancestors,
    textFingerprint: text,
    siblingIndex: siblingIndex,
  );
}
