import 'dart:io';

import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/cli/matcher_builder.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

class EnterTextCommand extends InstanceCommand {
  EnterTextCommand(this._registry) {
    argParser
      ..addOption('key', help: 'Element key (ValueKey<String>).')
      ..addOption('text', help: 'Visible text of the text field.')
      ..addFlag(
        'focused',
        help: 'Target the currently focused text field.',
        negatable: false,
      )
      ..addOption(
        'input',
        help: 'Text to enter into the field.',
        mandatory: true,
      )
      ..addOption('ref', help: 'Reference @N from a prior get-interactive-elements')
      ..addFlag('ensure-visible', defaultsTo: true, negatable: true, help: 'Auto-scroll element into view');
  }

  final InstanceRegistry _registry;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'enter-text';

  @override
  String get description => 'Enter text into a text field.';

  @override
  Future<int> execute(VmServiceConnector connector) async {
    final input = argResults!['input'] as String;
    final focused = argResults!['focused'] as bool;
    final matcher = buildMatcherFromArgs(
      key: argResults?['key'] as String?,
      text: argResults?['text'] as String?,
      focused: focused,
    );
    final ref = argResults?['ref'] as String?;
    if (ref != null) matcher['ref'] = ref;
    final ensureVisible = argResults!['ensure-visible'] as bool;
    if (!ensureVisible) matcher['ensureVisible'] = 'false';

    if (matcher.isEmpty) {
      usageException(
        'At least one matcher required: --key, --text, or --focused.',
      );
    }

    final response = await connector.enterText(matcher, input);
    final message =
        response['message'] as String? ?? 'Successfully entered text';
    stdout.writeln(message);
    return 0;
  }
}
