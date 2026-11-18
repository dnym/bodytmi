import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'lock.dart';
import 'profile.dart';
import 'theme.dart';
import 'widgets.dart';

/// Opens the profile at [path], asking for the passphrase or device unlock
/// first when it is encrypted, then shows the app.
final class BodyTmiRoot extends StatefulWidget {
  const BodyTmiRoot({
    super.key,
    required this.path,
    required this.keyStore,
    this.clock,
  });

  final String path;
  final DeviceKeyStore keyStore;
  final DateTime? clock;

  @override
  State<BodyTmiRoot> createState() => _BodyTmiRootState();
}

final class _BodyTmiRootState extends State<BodyTmiRoot> {
  ProfileClient? profile;
  LockMode? mode;
  bool encrypted = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final saved = await LockSettings.read(widget.path);
    encrypted = profileEncrypted(widget.path);
    if (!encrypted) {
      final p = await ProfileClient.open(
        widget.path,
        keyStore: widget.keyStore,
      );
      if (saved != LockMode.none) {
        await LockSettings.write(widget.path, LockMode.none);
      }
      setState(() => profile = p);
      return;
    }
    setState(() => mode = saved == LockMode.none ? LockMode.passphrase : saved);
  }

  @override
  Widget build(BuildContext context) {
    if (profile != null) {
      return BodyTmiApp(profile: profile!, clock: widget.clock);
    }
    return MaterialApp(
      title: 'BodyTMI',
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      home: mode == null
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : UnlockScreen(
              path: widget.path,
              mode: mode!,
              keyStore: widget.keyStore,
              onUnlocked: (p) => setState(() => profile = p),
            ),
    );
  }
}

/// Asks for the passphrase, or runs device unlock, for an encrypted profile.
/// Both are offered: the saved mode only decides which comes first.
final class UnlockScreen extends StatefulWidget {
  const UnlockScreen({
    super.key,
    required this.path,
    required this.mode,
    required this.keyStore,
    required this.onUnlocked,
  });

  final String path;
  final LockMode mode;
  final DeviceKeyStore keyStore;
  final ValueChanged<ProfileClient> onUnlocked;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

final class _UnlockScreenState extends State<UnlockScreen> {
  final passphrase = TextEditingController();
  String? problem;
  bool busy = false;
  bool hidden = true;

  @override
  void initState() {
    super.initState();
    if (widget.mode == LockMode.device) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _device());
    }
  }

  @override
  void dispose() {
    passphrase.dispose();
    super.dispose();
  }

  Future<void> _open(ProfileKey key, LockMode mode) async {
    final profile = await ProfileClient.open(
      widget.path,
      key: key,
      lock: mode,
      keyStore: widget.keyStore,
    );
    await LockSettings.write(widget.path, mode);
    widget.onUnlocked(profile);
  }

  Future<void> _device() async {
    setState(() {
      busy = true;
      problem = null;
    });
    try {
      final key = await widget.keyStore.read();
      if (key == null) {
        throw const BodyTmiException(
          'locked',
          'No device key is stored on this phone; use the passphrase.',
        );
      }
      await _open(ProfileKey.fromText(key), LockMode.device);
    } on BodyTmiException catch (e) {
      if (mounted) setState(() => problem = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _passphrase() async {
    setState(() {
      busy = true;
      problem = null;
    });
    try {
      await _open(ProfileKey.fromText(passphrase.text), LockMode.passphrase);
    } on BodyTmiException catch (e) {
      if (mounted) setState(() => problem = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.mode == LockMode.device;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'BodyTMI is locked',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 24),
                  if (device) ...[
                    FilledButton.icon(
                      onPressed: busy ? null : _device,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Unlock'),
                    ),
                    const SizedBox(height: 24),
                    const Muted(
                      'If this profile was locked with a passphrase, enter it:',
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: passphrase,
                    obscureText: hidden,
                    autofocus: !device,
                    onSubmitted: (_) => busy ? null : _passphrase(),
                    decoration: InputDecoration(
                      labelText: 'Passphrase',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: hidden ? 'Show' : 'Hide',
                        onPressed: () => setState(() => hidden = !hidden),
                        icon: Icon(
                          hidden ? Icons.visibility : Icons.visibility_off,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  (device ? OutlinedButton.new : FilledButton.new)(
                    onPressed: busy ? null : _passphrase,
                    child: const Text('Unlock with passphrase'),
                  ),
                  if (!device) ...[
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: busy ? null : _device,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Use device unlock'),
                    ),
                  ],
                  if (problem != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        problem!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
