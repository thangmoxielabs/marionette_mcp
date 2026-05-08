import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/services/hit_test_utils.dart';
import 'package:marionette_flutter/src/services/snapshot_options.dart';
import 'package:marionette_flutter/src/services/snapshot_session.dart';
import 'package:marionette_flutter/src/services/stable_identity.dart';

/// Result of a snapshot with metadata.
class SnapshotResult {
  SnapshotResult({
    required this.elements,
    this.truncated = false,
    this.screenName,
    this.routeName,
  });
  final List<Map<String, dynamic>> elements;
  final bool truncated;
  final String? screenName;
  final String? routeName;
}

class _VisitMetaResult {
  _VisitMetaResult({this.screenName, this.routeName});
  final String? screenName;
  final String? routeName;
}

/// Finds and extracts interactive elements from the Flutter widget tree.
class ElementTreeFinder {
  const ElementTreeFinder(this.configuration);

  final MarionetteConfiguration configuration;

  /// Returns a list of interactive elements from the current widget tree.
  List<Map<String, dynamic>> findInteractiveElements({
    SnapshotOptions options = const SnapshotOptions(),
  }) {
    return findInteractiveElementsWithMeta(options: options).elements;
  }

  /// Returns a [SnapshotResult] with elements and metadata (truncated, screenName, routeName).
  SnapshotResult findInteractiveElementsWithMeta({
    SnapshotOptions options = const SnapshotOptions(),
  }) {
    SnapshotSession.instance.beginSnapshot();
    final elements = <Map<String, dynamic>>[];
    final rootElement = WidgetsBinding.instance.rootElement;

    String? screenName;
    String? routeName;

    if (rootElement != null) {
      final result = _visitElementWithMeta(
        rootElement,
        elements,
        options: options,
        screenName: screenName,
        routeName: routeName,
      );
      screenName = result.screenName;
      routeName = result.routeName;
    }

    final truncated = options.limit != null && elements.length == options.limit!;

    return SnapshotResult(
      elements: elements,
      truncated: truncated,
      screenName: screenName,
      routeName: routeName,
    );
  }

  _VisitMetaResult _visitElementWithMeta(
    Element element,
    List<Map<String, dynamic>> result, {
    SnapshotOptions options = const SnapshotOptions(),
    Map<String, int>? siblingCounters,
    String? parentRef,
    String? screenName,
    String? routeName,
  }) {
    final widget = element.widget;

    if (options.prune && widget is Offstage && widget.offstage) {
      return _VisitMetaResult(screenName: screenName, routeName: routeName);
    }

    if (options.limit != null && result.length >= options.limit!) {
      return _VisitMetaResult(screenName: screenName, routeName: routeName);
    }

    final myType = widget.runtimeType.toString();
    final myIndex = (siblingCounters ?? const <String, int>{})[myType] ?? 0;
    final ownCounters = <String, int>{...?siblingCounters};
    ownCounters[myType] = myIndex + 1;

    if (widget is Scaffold) {
      screenName = _extractScreenName(widget);
    }

    final elementData = _extractElementData(
      element,
      widget,
      options: options,
      siblingIndex: myIndex,
    );

    if (elementData != null) {
      if (parentRef != null) elementData['parentRef'] = parentRef;
      result.add(elementData);
    }

    if (configuration.shouldStopAtType(widget.runtimeType)) {
      return _VisitMetaResult(screenName: screenName, routeName: routeName);
    }

    final myRef = elementData?['ref'] as String?;
    element.visitChildren((child) {
      final r = _visitElementWithMeta(
        child,
        result,
        options: options,
        siblingCounters: ownCounters,
        parentRef: myRef ?? parentRef,
        screenName: screenName,
        routeName: routeName,
      );
      screenName = r.screenName;
      routeName = r.routeName;
    });

    return _VisitMetaResult(screenName: screenName, routeName: routeName);
  }

  String? _extractScreenName(Scaffold scaffold) {
    final appBar = scaffold.appBar;
    if (appBar is PreferredSizeWidget) {
      // Can't easily extract title here without building; skip for now.
    }
    return null;
  }

  Map<String, dynamic>? _extractElementData(
    Element element,
    Widget widget, {
    SnapshotOptions options = const SnapshotOptions(),
    int siblingIndex = 0,
  }) {
    // Only process elements with render objects
    final renderObject = element.renderObject;
    if (renderObject == null) {
      return null;
    }

    // Check if this is an interactive or meaningful widget
    final isInteractive = configuration.isInteractiveWidgetType(
      widget.runtimeType,
    );
    final text = configuration.extractTextFromWidget(element);
    // Discovery-only Semantics fallback: if the standard matcher path yielded
    // no text, surface explicit accessibility annotations so agents can read
    // content rendered via inline-span trees, custom painters, or third-party
    // rich-text packages. Kept separate from extractTextFromWidget so that
    // TextMatcher (tap/scroll_to/enter_text) is not affected — otherwise a
    // Semantics(label: 'Save', child: ElevatedButton(...)) wrapper would
    // shadow the inner button.
    final discoverableText = text ?? _extractSemanticsText(widget);
    final keyValue = _extractKeyValue(widget.key);

    if (!isInteractive && discoverableText == null && keyValue == null) {
      return null;
    }

    // Only return widgets that can be hit
    if (!isElementHittable(element)) {
      return null;
    }

    final properties = DiagnosticPropertiesBuilder();
    widget.debugFillProperties(properties);
    final data = Map<String, Object>.fromEntries(
      properties.properties
          .where((p) =>
              p.runtimeType != DiagnosticsProperty &&
              p.name != null &&
              p.value != null)
          .map(
            (p) => MapEntry(p.name!, p.value.toString()),
          ),
    );

    final customProperties = configuration.extractProperties?.call(element);
    if (customProperties != null) {
      data.addAll(customProperties);
    }

    data['type'] = widget.runtimeType.toString();

    if (keyValue != null) {
      data['key'] = keyValue;
    }

    if (discoverableText != null) {
      data['text'] = discoverableText;
    }

    // Get position and size if available
    if (renderObject is RenderBox && renderObject.hasSize) {
      try {
        final offset = renderObject.localToGlobal(Offset.zero);
        final size = renderObject.size;
        data['bounds'] = {
          'x': offset.dx,
          'y': offset.dy,
          'width': size.width,
          'height': size.height,
        };
      } catch (_) {
        // Ignore if we can't get bounds
      }
    }

    // Check visibility
    data['visible'] = _isElementVisible(renderObject);

    if (options.compact) {
      const compactCoreKeys = {'type', 'text', 'key', 'bounds', 'visible', 'ref', 'parentRef'};
      const compactAllowList = {'enabled', 'value', 'selected', 'checked'};
      data.removeWhere((k, _) => !compactCoreKeys.contains(k) && !compactAllowList.contains(k));
    }

    final identity = _buildIdentity(element, widget, discoverableText, siblingIndex);
    final ref = SnapshotSession.instance.assign(identity);
    data['ref'] = ref;

    return data;
  }

  StableIdentity _buildIdentity(Element element, Widget widget, String? text, int siblingIndex) {
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

  String? _extractKeyValue(Key? key) {
    if (key is ValueKey<String>) {
      return key.value;
    }
    return null;
  }

  /// Discovery-only fallback: extracts the accessibility annotation from a
  /// `Semantics` widget.
  ///
  /// Combines `label` and `value` the way screen readers announce them
  /// (`'label: value'`) so widgets that set both — e.g.
  /// `Semantics(label: 'Volume', value: '70%')` — keep their dynamic state
  /// in the discovery output instead of dropping `value` when `label` is
  /// also present. Falls back to whichever field is non-empty when only one
  /// is set, and returns null when neither carries content.
  ///
  /// This is intentionally kept out of [MarionetteConfiguration.extractTextFromWidget]
  /// so that [TextMatcher] is not affected by Semantics wrappers — see the
  /// class-level dartdoc on `MarionetteConfiguration` for the rationale.
  static String? _extractSemanticsText(Widget widget) {
    if (widget is! Semantics) return null;
    final label = widget.properties.label;
    final value = widget.properties.value;
    final hasLabel = label != null && label.isNotEmpty;
    final hasValue = value != null && value.isNotEmpty;
    if (hasLabel && hasValue) return '$label: $value';
    if (hasLabel) return label;
    if (hasValue) return value;
    return null;
  }

  /// Checks if the element is currently visible on screen.
  bool _isElementVisible(RenderObject? renderObject) {
    if (renderObject == null || !renderObject.attached) {
      return false;
    }

    if (renderObject is RenderBox) {
      if (!renderObject.hasSize) {
        return false;
      }

      final size = renderObject.size;
      if (size.width <= 0 || size.height <= 0) {
        return false;
      }

      try {
        final offset = renderObject.localToGlobal(Offset.zero);
        final screenSize = WidgetsBinding
                .instance.platformDispatcher.views.first.physicalSize /
            WidgetsBinding
                .instance.platformDispatcher.views.first.devicePixelRatio;

        final isOnScreen = offset.dx + size.width >= 0 &&
            offset.dy + size.height >= 0 &&
            offset.dx < screenSize.width &&
            offset.dy < screenSize.height;

        return isOnScreen;
      } catch (_) {
        return true;
      }
    }

    return true;
  }
}
