import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/services/hit_test_utils.dart';
import 'package:marionette_flutter/src/services/snapshot_session.dart';
import 'package:marionette_flutter/src/services/widget_matcher.dart';

/// Result of a widget find operation.
sealed class FindResult {
  const FindResult();
}

/// Successfully found an element.
class FoundElement extends FindResult {
  FoundElement(this.element);
  final Element element;
}

/// Failed to find an element with a specific error code.
class FindError extends FindResult {
  FindError(this.code);
  final String code; // 'not-found', 'ref-unknown', 'ref-stale', 'ref-ambiguous'
}

/// Finds widgets in the Flutter widget tree using various matching criteria.
class WidgetFinder {
  /// Finds the first element that matches the given [matcher].
  ///
  /// Traverses the widget tree starting from the root element and returns
  /// the first element whose widget matches the provided matcher.
  ///
  /// Returns null if no matching element is found.
  Element? findElement(
    WidgetMatcher matcher,
    MarionetteConfiguration configuration,
  ) {
    return findElementFrom(
      matcher,
      WidgetsBinding.instance.rootElement,
      configuration,
    );
  }

  /// Finds the first element that matches the given [matcher] within the subtree
  /// rooted at the given [startElement].
  ///
  /// Returns null if no matching element is found.
  Element? findElementFrom(
    WidgetMatcher matcher,
    Element? startElement,
    MarionetteConfiguration configuration,
  ) {
    if (startElement == null) {
      return null;
    }

    Element? found;

    void visitor(Element element) {
      if (found != null) {
        return;
      } else if (matcher.matches(element, configuration)) {
        found = element;
      } else {
        element.visitChildren(visitor);
      }
    }

    visitor(startElement);
    return found;
  }

  /// Finds the first element that matches the given [matcher] and is hittable
  /// (i.e. can receive pointer events and is not behind a modal barrier).
  ///
  /// This should be used by tools that dispatch gestures (tap, enter_text)
  /// where matching a non-hittable widget would result in a silent failure.
  /// Tools that need to find offscreen elements (e.g. scroll_to) should use
  /// [findElement] instead.
  ///
  /// Returns a [FindResult] — either [FoundElement] or [FindError] with a
  /// specific error code for ref-based matchers.
  FindResult findHittableElement(
    WidgetMatcher matcher,
    MarionetteConfiguration configuration,
  ) {
    return _findHittableElementFrom(
      matcher,
      WidgetsBinding.instance.rootElement,
      configuration,
    );
  }

  FindResult _findHittableElementFrom(
    WidgetMatcher matcher,
    Element? startElement,
    MarionetteConfiguration configuration,
  ) {
    if (startElement == null) {
      return FindError('not-found');
    }

    // Special handling for RefMatcher: check session first
    if (matcher is RefMatcher) {
      final stored = SnapshotSession.instance.lookup(matcher.ref);
      if (stored == null) {
        return FindError('ref-unknown');
      }
      // Walk tree to find all matches
      final matches = <Element>[];
      void visitor(Element element) {
        if (matcher.matches(element, configuration) && isElementHittable(element)) {
          matches.add(element);
        } else {
          element.visitChildren(visitor);
        }
      }
      visitor(startElement);
      if (matches.isEmpty) return FindError('ref-stale');
      if (matches.length > 1) return FindError('ref-ambiguous');
      return FoundElement(matches.first);
    }

    Element? found;

    void visitor(Element element) {
      if (found != null) {
        return;
      } else if (matcher.matches(element, configuration) &&
          isElementHittable(element)) {
        found = element;
      } else {
        element.visitChildren(visitor);
      }
    }

    visitor(startElement);
    return found != null ? FoundElement(found!) : FindError('not-found');
  }
}
