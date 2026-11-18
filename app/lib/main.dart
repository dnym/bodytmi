import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'src/app.dart';
import 'src/profile.dart';

/// Opens the profile in the app's private storage and starts the GUI.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await getApplicationSupportDirectory();
  final profile = await ProfileClient.open('${directory.path}/profile.sqlite');
  runApp(BodyTmiApp(profile: profile));
}
