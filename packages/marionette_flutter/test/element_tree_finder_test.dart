import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/services/element_tree_finder.dart';

void main() {
  group('extractProperties', () {
    testWidgets('custom properties are included in element data',
        (tester) async {
      final configuration = MarionetteConfiguration(
        extractProperties: (element) {
          final widget = element.widget;
          if (widget is ElevatedButton) {
            return {
              'enabled': widget.enabled,
              'customTag': 'primary',
            };
          }
          return null;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ElevatedButton(
              key: const ValueKey('btn'),
              onPressed: () {},
              child: const Text('Tap me'),
            ),
          ),
        ),
      );

      final finder = ElementTreeFinder(configuration);
      final elements = finder.findInteractiveElements();

      final btn = elements.firstWhere((e) => e['key'] == 'btn');
      expect(btn['enabled'], true);
      expect(btn['customTag'], 'primary');
    });

    testWidgets('custom properties override debugFillProperties values',
        (tester) async {
      final configuration = MarionetteConfiguration(
        extractProperties: (element) {
          if (element.widget is Slider) {
            return {'value': 'custom_override'};
          }
          return null;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Slider(
              key: const ValueKey('slider'),
              value: 0.5,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final finder = ElementTreeFinder(configuration);
      final elements = finder.findInteractiveElements();

      final slider = elements.firstWhere((e) => e['key'] == 'slider');
      expect(slider['value'], 'custom_override');
    });

    testWidgets('null return from extractProperties adds nothing',
        (tester) async {
      final configuration = MarionetteConfiguration(
        extractProperties: (element) => null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ElevatedButton(
              key: const ValueKey('btn'),
              onPressed: () {},
              child: const Text('Tap'),
            ),
          ),
        ),
      );

      final finder = ElementTreeFinder(configuration);
      final elements = finder.findInteractiveElements();

      final btn = elements.firstWhere((e) => e['key'] == 'btn');
      expect(btn['type'], 'ElevatedButton');
    });

    testWidgets('works with isInteractiveWidget for custom widgets',
        (tester) async {
      final configuration = MarionetteConfiguration(
        isInteractiveWidget: (type) => type == Card,
        extractProperties: (element) {
          if (element.widget is Card) {
            return {'role': 'action-card'};
          }
          return null;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Card(
              key: const ValueKey('card'),
              child: const Text('Content'),
            ),
          ),
        ),
      );

      final finder = ElementTreeFinder(configuration);
      final elements = finder.findInteractiveElements();

      final card = elements.firstWhere((e) => e['key'] == 'card');
      expect(card['role'], 'action-card');
      expect(card['type'], 'Card');
    });
  });
}
