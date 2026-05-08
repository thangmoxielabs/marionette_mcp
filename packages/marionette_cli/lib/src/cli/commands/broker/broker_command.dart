import 'package:args/command_runner.dart';

import 'start_command.dart';
import 'status_command.dart';
import 'stop_command.dart';

class BrokerCommand extends Command<int> {
  @override
  String get name => 'broker';

  @override
  String get description => 'Manage the local Marionette broker server.';

  BrokerCommand() {
    addSubcommand(BrokerStartCommand());
    addSubcommand(BrokerStatusCommand());
    addSubcommand(BrokerStopCommand());
  }
}
