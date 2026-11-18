import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'src/lock.dart';
import 'src/unlock.dart';

/// Opens the profile in the app's private storage, unlocking it first when
/// it is encrypted, and starts the GUI.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await getApplicationSupportDirectory();
  runApp(
    BodyTmiRoot(
      path: '${directory.path}/profile.sqlite',
      keyStore: KeystoreDeviceKeyStore(),
    ),
  );
}
