import 'package:bodytmi_core/bodytmi_core.dart';

import 'commands.dart';
import 'daily_commands.dart';
import 'food_commands.dart';
import 'planning_commands.dart';
import 'sleep_commands.dart';
import 'stored_commands.dart';

/// Whether [command] (`<group> <action>`) is a known command.
bool isCommand(String command) =>
    commandNames.contains(command) ||
    storedCommandNames.contains(command) ||
    foodCommandNames.contains(command) ||
    sleepCommandNames.contains(command) ||
    dailyCommandNames.contains(command) ||
    planningCommandNames.contains(command);

/// Runs one JSON command in this process, as the CLI does: the same
/// request and response envelopes, errors as [BodyTmiException].
Future<Map<String, Object?>> executeCommand(
  String command,
  Map<String, Object?> request,
) async {
  if (planningCommandNames.contains(command))
    return executePlanning(command, request);
  if (dailyCommandNames.contains(command))
    return executeDaily(command, request);
  if (sleepCommandNames.contains(command))
    return executeSleep(command, request);
  if (foodCommandNames.contains(command)) return executeFood(command, request);
  if (storedCommandNames.contains(command))
    return executeStored(command, request);
  if (commandNames.contains(command))
    return const Commands().execute(command, request);
  throw const BodyTmiException('usage', 'Unknown command/option. Use --help.');
}
