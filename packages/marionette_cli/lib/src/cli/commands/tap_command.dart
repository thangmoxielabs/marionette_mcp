import 'dart:io';

import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/cli/matcher_builder.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

class TapCommand extends InstanceCommand {
  TapCommand(this._registry) {
    argParser
      ..addOption('key', help: 'Element key (ValueKey<String>).')
      ..addOption('text', help: 'Visible text content of the element.')
      ..addOption('type', help: 'Widget type name (e.g., ElevatedButton).')
      ..addOption('x', help: 'X coordinate for positional tap.')
      ..addOption('y', help: 'Y coordinate for positional tap.')
      ..addOption('ref', help: 'Reference @N from a prior get-interactive-elements')
      ..addFlag('ensure-visible', defaultsTo: true, negatable: true, help: 'Auto-scroll element into view');
  }

  final InstanceRegistry _registry;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'tap';

  @override
  String get description =>
      'Tap an element by key, text, type, or coordinates.';

  @override
  Future<int> execute(VmServiceConnector connector) async {
    final matcher = buildMatcherFromArgs(
      key: argResults?['key'] as String?,
      text: argResults?['text'] as String?,
      type: argResults?['type'] as String?,
      x: _parseNum(argResults?['x'] as String?),
      y: _parseNum(argResults?['y'] as String?),
    );
    final ref = argResults?['ref'] as String?;
    if (ref != null) matcher['ref'] = ref;

    if (matcher.isEmpty) {
      usageException(
        'At least one matcher required: --key, --text, --type, --ref, or --x/--y.',
      );
    }

    final ensureVisible = argResults!['ensure-visible'] as bool;
    if (!ensureVisible) matcher['ensureVisible'] = 'false';

    final response = await connector.tap(matcher);
    if (response.containsKey('error')) {
      stderr.writeln('Error: ${response['error']}');
      return 1;
    }
    final message = response['message'] as String? ?? 'Successfully tapped';
    stdout.writeln(message);
    return 0;
  }

  num? _parseNum(String? value) {
    if (value == null) return null;
    return num.tryParse(value);
  }
}
