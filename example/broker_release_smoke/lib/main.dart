import 'package:flutter/material.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

void main() {
  MarionetteBinding.ensureInitialized(
    MarionetteConfiguration(
      enableBroker: const BrokerOptions(),
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Broker Smoke Test',
      home: Scaffold(
        appBar: AppBar(title: const Text('Broker Smoke Test')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                key: const ValueKey('smoke_button'),
                onPressed: () {},
                child: const Text('Tap Me'),
              ),
              const SizedBox(height: 16),
              const TextField(
                key: ValueKey('smoke_textfield'),
                decoration: InputDecoration(labelText: 'Enter text'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
