import 'dart:io';

import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/formatting.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

class ElementsCommand extends InstanceCommand {
  ElementsCommand(this._registry) {
    argParser
      ..addFlag('compact', help: 'Strip debugFillProperties bulk; use allow-list')
      ..addFlag('prune', help: 'Skip Offstage / non-current-route / zero-size')
      ..addOption('limit', help: 'Cap on entries; sets truncated:true if hit')
      ..addFlag('viewport-only', help: 'Only entries intersecting screen')
      ..addOption('scope', help: 'Ref (@N) or selector to root snapshot');
  }

  final InstanceRegistry _registry;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'get-interactive-elements';

  @override
  String get description =>
      'List interactive elements in the Flutter app UI tree.';

  @override
  Future<int> execute(VmServiceConnector connector) async {
    final params = <String, dynamic>{};
    if (argResults!['compact'] as bool) params['compact'] = 'true';
    if (argResults!['prune'] as bool) params['prune'] = 'true';
    final limit = argResults!['limit'] as String?;
    if (limit != null) params['limit'] = limit;
    if (argResults!['viewport-only'] as bool) params['viewportOnly'] = 'true';
    final scope = argResults!['scope'] as String?;
    if (scope != null) params['scope'] = scope;

    final response = await connector.getInteractiveElements(params: params);
    final elements = response['elements'] as List<dynamic>;
    final truncated = response['truncated'] as bool?;
    final screenName = response['screenName'] as String?;
    final routeName = response['routeName'] as String?;

    stdout.writeln('Found ${elements.length} interactive element(s):');
    if (truncated == true) stdout.writeln('(truncated)');
    if (screenName != null) stdout.writeln('Screen: $screenName');
    if (routeName != null) stdout.writeln('Route: $routeName');
    stdout.writeln();

    for (final element in elements) {
      stdout.writeln(formatElement(element as Map<String, dynamic>));
    }

    return 0;
  }
}
