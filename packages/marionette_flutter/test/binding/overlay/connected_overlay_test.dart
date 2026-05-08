import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/binding/overlay/connected_overlay.dart';

void main() {
  testWidgets('ConnectedOverlay is visible when connected is true', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const SizedBox(),
              const ConnectedOverlay(connected: true),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Marionette connected'), findsOneWidget);
  });

  testWidgets('ConnectedOverlay is hidden when connected is false', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const SizedBox(),
              const ConnectedOverlay(connected: false),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Marionette connected'), findsNothing);
  });

  testWidgets('ConnectedOverlay respects showOverlay flag', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const SizedBox(),
              const ConnectedOverlay(connected: true, showOverlay: false),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Marionette connected'), findsNothing);
  });
}
