import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/services/snapshot_session.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';
import 'package:marionette_flutter/src/services/widget_matcher.dart';

/// Dispatches gesture events to simulate user interactions.
class GestureDispatcher {
  static const kMaxDelta = 40.0;
  static const kDelay = Duration(milliseconds: 10);

  static const _kDeviceId = 1;
  static const _kSecondDeviceId = 2;

  int _nextPointerId = 1;

  /// Simulates a tap on an element that matches the given [matcher].
  ///
  /// If [matcher] is a [CoordinatesMatcher], taps directly at the specified
  /// coordinates without searching the widget tree (fast path).
  ///
  /// If [ensureVisible] is true (default) and the matcher is a [RefMatcher],
  /// attempts to scroll the element into view if it exists but is not hittable.
  Future<FindResult> tap(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    MarionetteConfiguration configuration, {
    bool ensureVisible = true,
  }) async {
    // Fast path for coordinate-based tapping
    if (matcher is CoordinatesMatcher) {
      await _dispatchTapAtPosition(matcher.offset);
      return FoundElement(WidgetsBinding.instance.rootElement!);
    }

    var result = widgetFinder.findHittableElement(matcher, configuration);

    // Auto-rescroll for RefMatcher if not hittable but ensureVisible is true
    if (result is FindError && matcher is RefMatcher && ensureVisible) {
      result = await _ensureVisibleIfNeeded(matcher, widgetFinder, configuration);
    }

    if (result is FoundElement) {
      await _dispatchTapAtElement(result.element);
    }
    return result;
  }

  /// Attempts to find a non-hittable element matching [matcher], scroll it
  /// into view via the nearest Scrollable ancestor, then re-find as hittable.
  Future<FindResult> _ensureVisibleIfNeeded(
    RefMatcher matcher,
    WidgetFinder widgetFinder,
    MarionetteConfiguration configuration,
  ) async {
    // Check session first
    final stored = SnapshotSession.instance.lookup(matcher.ref);
    if (stored == null) {
      return FindError('ref-unknown');
    }

    // Find the element without hittability check
    final element = widgetFinder.findElement(matcher, configuration);
    if (element == null) {
      return FindError('ref-stale');
    }

    // Find nearest Scrollable ancestor
    ScrollableState? scrollable;
    element.visitAncestorElements((ancestor) {
      if (ancestor is StatefulElement && ancestor.state is ScrollableState) {
        scrollable = ancestor.state as ScrollableState;
        return false;
      }
      return true;
    });

    if (scrollable != null) {
      try {
        await Scrollable.ensureVisible(
          element,
          duration: Duration.zero,
          alignment: 0.5,
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      } catch (_) {
        // If ensureVisible fails, continue and try to tap anyway
      }
    }

    // Re-find with hittability check
    return widgetFinder.findHittableElement(matcher, configuration);
  }

  Future<void> _dispatchTapAtElement(Element element) async {
    final renderObject = element.renderObject;

    if (renderObject is! RenderBox) {
      throw Exception('Element does not have a RenderBox');
    }

    if (!renderObject.hasSize) {
      throw Exception('RenderBox does not have a size yet');
    }

    // Get the center position of the widget
    final center = renderObject.size.center(Offset.zero);
    final globalPosition = renderObject.localToGlobal(center);

    await _dispatchTapAtPosition(globalPosition);
  }

  Future<void> _dispatchTapAtPosition(Offset globalPosition) async {
    final pointerId = _nextPointerId++;

    // Build the event records
    final records = [
      // Pointer down immediately
      [
        PointerAddedEvent(position: globalPosition, device: _kDeviceId),
        PointerDownEvent(
            pointer: pointerId, position: globalPosition, device: _kDeviceId),
      ],
      // Pointer up after a short delay, then remove the device
      [
        PointerUpEvent(
            pointer: pointerId, position: globalPosition, device: _kDeviceId),
        PointerRemovedEvent(position: globalPosition, device: _kDeviceId),
      ],
    ];

    await _handlePointerEventRecord(records);
  }

  /// Simulates a double tap on an element that matches the given [matcher].
  ///
  /// Two taps are dispatched with [delay] between them.
  /// Defaults to 100ms, which is within Flutter's double-tap recognition
  /// window (kDoubleTapMinTime 40ms — kDoubleTapTimeout 300ms).
  Future<FindResult> doubleTap(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    MarionetteConfiguration configuration, {
    Duration delay = const Duration(milliseconds: 100),
    bool ensureVisible = true,
  }) async {
    if (delay.isNegative || delay == Duration.zero) {
      throw ArgumentError('delay must be positive');
    }

    if (matcher is CoordinatesMatcher) {
      await _dispatchDoubleTapAtPosition(matcher.offset, delay);
      return FoundElement(WidgetsBinding.instance.rootElement!);
    }

    var result = widgetFinder.findHittableElement(matcher, configuration);

    if (result is FindError && matcher is RefMatcher && ensureVisible) {
      result = await _ensureVisibleIfNeeded(matcher, widgetFinder, configuration);
    }

    if (result is FoundElement) {
      await _dispatchDoubleTapAtElement(result.element, delay);
    }
    return result;
  }

  Future<void> _dispatchDoubleTapAtElement(
    Element element,
    Duration delay,
  ) async {
    final renderObject = element.renderObject;

    if (renderObject is! RenderBox) {
      throw Exception('Element does not have a RenderBox');
    }

    if (!renderObject.hasSize) {
      throw Exception('RenderBox does not have a size yet');
    }

    final center = renderObject.size.center(Offset.zero);
    final globalPosition = renderObject.localToGlobal(center);

    await _dispatchDoubleTapAtPosition(globalPosition, delay);
  }

  Future<void> _dispatchDoubleTapAtPosition(
    Offset globalPosition,
    Duration delay,
  ) async {
    // First tap
    await _dispatchTapAtPosition(globalPosition);

    // Wait between taps for double-tap recognition
    await Future<void>.delayed(delay);

    // Second tap
    await _dispatchTapAtPosition(globalPosition);
  }

  /// Simulates a long press on an element that matches the given [matcher].
  ///
  /// The pointer is held down for [duration] before being released.
  /// Defaults to 600ms (kLongPressTimeout + kPressTimeout), matching
  /// Flutter's [WidgetTester.longPress] behavior.
  Future<FindResult> longPress(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    MarionetteConfiguration configuration, {
    Duration duration = const Duration(milliseconds: 600),
    bool ensureVisible = true,
  }) async {
    if (duration.isNegative || duration == Duration.zero) {
      throw ArgumentError('duration must be positive');
    }

    if (matcher is CoordinatesMatcher) {
      await _dispatchLongPressAtPosition(matcher.offset, duration);
      return FoundElement(WidgetsBinding.instance.rootElement!);
    }

    var result = widgetFinder.findHittableElement(matcher, configuration);

    if (result is FindError && matcher is RefMatcher && ensureVisible) {
      result = await _ensureVisibleIfNeeded(matcher, widgetFinder, configuration);
    }

    if (result is FoundElement) {
      await _dispatchLongPressAtElement(result.element, duration);
    }
    return result;
  }

  Future<void> _dispatchLongPressAtElement(
    Element element,
    Duration duration,
  ) async {
    final renderObject = element.renderObject;

    if (renderObject is! RenderBox) {
      throw Exception('Element does not have a RenderBox');
    }

    if (!renderObject.hasSize) {
      throw Exception('RenderBox does not have a size yet');
    }

    final center = renderObject.size.center(Offset.zero);
    final globalPosition = renderObject.localToGlobal(center);

    await _dispatchLongPressAtPosition(globalPosition, duration);
  }

  Future<void> _dispatchLongPressAtPosition(
    Offset globalPosition,
    Duration duration,
  ) async {
    final pointerId = _nextPointerId++;

    final records = [
      [
        PointerAddedEvent(position: globalPosition, device: _kDeviceId),
        PointerDownEvent(
            pointer: pointerId, position: globalPosition, device: _kDeviceId),
      ],
    ];

    // Dispatch pointer down
    await _handlePointerEventRecord(records);

    // Hold for the specified duration to trigger long press recognition
    await Future<void>.delayed(duration);

    // Release
    await _handlePointerEventRecord([
      [
        PointerUpEvent(
            pointer: pointerId, position: globalPosition, device: _kDeviceId),
        PointerRemovedEvent(position: globalPosition, device: _kDeviceId),
      ],
    ]);
  }

  /// Simulates a swipe gesture on an element matching [matcher] in the given
  /// [direction] for [distance] pixels.
  ///
  /// The swipe starts from the center of the matched element and moves in the
  /// specified direction.
  Future<void> swipe(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    MarionetteConfiguration configuration, {
    required String direction,
    double distance = 200.0,
  }) async {
    final element = widgetFinder.findElement(matcher, configuration);

    if (element == null) {
      throw Exception('Element matching ${matcher.toJson()} not found');
    }

    final renderObject = element.renderObject;
    if (renderObject is! RenderBox) {
      throw Exception('Element does not have a RenderBox');
    }

    if (!renderObject.hasSize) {
      throw Exception('RenderBox does not have a size yet');
    }

    final center = renderObject.size.center(Offset.zero);
    final start = renderObject.localToGlobal(center);

    final end = switch (direction) {
      'left' => start + Offset(-distance, 0),
      'right' => start + Offset(distance, 0),
      'up' => start + Offset(0, -distance),
      'down' => start + Offset(0, distance),
      _ => throw ArgumentError('Invalid direction: $direction. '
          'Must be one of: left, right, up, down'),
    };

    await drag(start, end);
  }

  /// Simulates a pinch zoom gesture centered on an element matching [matcher].
  ///
  /// [scale] controls the zoom:
  /// - scale > 1.0: zoom in (fingers move apart)
  /// - scale < 1.0: zoom out (fingers move together)
  ///
  /// [startDistance] is the initial distance between the two fingers in pixels.
  Future<FindResult> pinchZoom(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    MarionetteConfiguration configuration, {
    required double scale,
    double startDistance = 200.0,
  }) async {
    if (scale <= 0) {
      throw ArgumentError('scale must be positive');
    }
    if (startDistance <= 0) {
      throw ArgumentError('startDistance must be positive');
    }

    if (matcher is CoordinatesMatcher) {
      await _dispatchPinchZoomAtPosition(
        matcher.offset,
        scale: scale,
        startDistance: startDistance,
      );
      return FoundElement(WidgetsBinding.instance.rootElement!);
    }

    final result = widgetFinder.findHittableElement(matcher, configuration);

    if (result is! FoundElement) {
      return result;
    }

    final renderObject = result.element.renderObject;
    if (renderObject is! RenderBox) {
      throw Exception('Element does not have a RenderBox');
    }

    if (!renderObject.hasSize) {
      throw Exception('RenderBox does not have a size yet');
    }

    final center = renderObject.size.center(Offset.zero);
    final globalCenter = renderObject.localToGlobal(center);

    await _dispatchPinchZoomAtPosition(
      globalCenter,
      scale: scale,
      startDistance: startDistance,
    );
    return result;
  }

  Future<void> _dispatchPinchZoomAtPosition(
    Offset center, {
    required double scale,
    required double startDistance,
  }) async {
    final pointer1Id = _nextPointerId++;
    final pointer2Id = _nextPointerId++;
    final endDistance = startDistance * scale;

    const stepCount = 10;

    // Finger positions: horizontally offset from center
    Offset finger1(double distance) => center - Offset(distance / 2, 0);
    Offset finger2(double distance) => center + Offset(distance / 2, 0);

    final start1 = finger1(startDistance);
    final start2 = finger2(startDistance);

    // Phase 1: Both fingers down
    final records = <List<PointerEvent>>[
      [
        PointerAddedEvent(position: start1, device: _kDeviceId),
        PointerDownEvent(
          pointer: pointer1Id,
          position: start1,
          device: _kDeviceId,
        ),
      ],
      [
        PointerAddedEvent(position: start2, device: _kSecondDeviceId),
        PointerDownEvent(
          pointer: pointer2Id,
          position: start2,
          device: _kSecondDeviceId,
        ),
      ],
    ];

    // Phase 2: Move fingers apart (zoom in) or together (zoom out)
    for (var i = 1; i <= stepCount; i++) {
      final t = i / stepCount;
      final currentDistance = startDistance + (endDistance - startDistance) * t;
      final pos1 = finger1(currentDistance);
      final pos2 = finger2(currentDistance);

      records.add([
        PointerMoveEvent(
          pointer: pointer1Id,
          position: pos1,
          device: _kDeviceId,
        ),
        PointerMoveEvent(
          pointer: pointer2Id,
          position: pos2,
          device: _kSecondDeviceId,
        ),
      ]);
    }

    // Phase 3: Both fingers up
    final end1 = finger1(endDistance);
    final end2 = finger2(endDistance);

    records.addAll([
      [
        PointerUpEvent(
          pointer: pointer1Id,
          position: end1,
          device: _kDeviceId,
        ),
        PointerUpEvent(
          pointer: pointer2Id,
          position: end2,
          device: _kSecondDeviceId,
        ),
      ],
      [
        PointerRemovedEvent(position: end1, device: _kDeviceId),
        PointerRemovedEvent(position: end2, device: _kSecondDeviceId),
      ],
    ]);

    await _handlePointerEventRecord(records);
  }

  /// Simulates a drag gesture from [from] to [to].
  Future<void> drag(Offset from, Offset to) async {
    final pointerId = _nextPointerId++;

    final delta = to - from;
    final distance = delta.distance;
    final stepCount =
        (distance / kMaxDelta).ceil().clamp(1, double.infinity).toInt();

    final moveRecords = <List<PointerEvent>>[];
    for (var i = 1; i <= stepCount; i++) {
      final t = i / stepCount;
      final position = Offset.lerp(from, to, t)!;
      final previousPosition =
          i == 1 ? from : Offset.lerp(from, to, (i - 1) / stepCount)!;
      final stepDelta = position - previousPosition;

      moveRecords.add([
        PointerMoveEvent(
          pointer: pointerId,
          position: position,
          delta: stepDelta,
          device: _kDeviceId,
        ),
      ]);
    }

    final records = [
      [
        PointerAddedEvent(position: from, device: _kDeviceId),
        PointerDownEvent(
            pointer: pointerId, position: from, device: _kDeviceId),
      ],
      ...moveRecords,
      [
        PointerUpEvent(pointer: pointerId, position: to, device: _kDeviceId),
        PointerRemovedEvent(position: to, device: _kDeviceId),
      ],
    ];

    await _handlePointerEventRecord(records);
  }

  /// Handles a list of pointer event records by dispatching them with proper timing.
  ///
  /// Similar to Flutter's test framework handlePointerEventRecord, but simplified
  /// for live app execution.
  Future<void> _handlePointerEventRecord(
    List<List<PointerEvent>> records,
  ) async {
    for (final record in records) {
      record.forEach(GestureBinding.instance.handlePointerEvent);
      WidgetsBinding.instance.scheduleFrame();
      await Future<void>.delayed(kDelay);
    }
  }
}
