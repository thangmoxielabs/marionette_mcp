import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/services/element_tree_finder.dart';
import 'package:marionette_flutter/src/services/gesture_dispatcher.dart';
import 'package:marionette_flutter/src/services/snapshot_session.dart';
import 'package:marionette_flutter/src/services/text_input_simulator.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';

void main() {
  setUp(() => SnapshotSession.instance.reset());

  testWidgets('describe → tap @N → enter_text @M chain', (tester) async {
    String? savedText;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            TextField(
              key: const ValueKey('input-field'),
              onChanged: (v) { savedText = v; },
            ),
            ElevatedButton(
              key: const ValueKey('save-btn'),
              onPressed: () {},
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    ));

    // Step 1: Describe to populate session
    final finder = ElementTreeFinder(const MarionetteConfiguration());
    final elements = finder.findInteractiveElements();

    final inputRef = elements.firstWhere((e) => e['key'] == 'input-field')['ref'] as String;
    final saveRef = elements.firstWhere((e) => e['key'] == 'save-btn')['ref'] as String;

    // Step 2: Tap the input field to focus it
    final dispatcher = GestureDispatcher();
    final tapResult = await tester.runAsync(() => dispatcher.tap(
      RefMatcher(inputRef),
      WidgetFinder(),
      const MarionetteConfiguration(),
    ));
    expect(tapResult, isA<FoundElement>());
    await tester.pump();

    // Step 3: Enter text into the focused field
    final textSimulator = TextInputSimulator(WidgetFinder());
    await textSimulator.enterText(
      const FocusedElementMatcher(),
      'Hello World',
      const MarionetteConfiguration(),
    );
    await tester.pump();

    expect(savedText, 'Hello World');

    // Step 4: Tap save button using its ref
    final saveResult = await tester.runAsync(() => dispatcher.tap(
      RefMatcher(saveRef),
      WidgetFinder(),
      const MarionetteConfiguration(),
    ));
    expect(saveResult, isA<FoundElement>());
  });
}
