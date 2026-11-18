import 'dart:io';

import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'backup.dart';
import 'journal.dart';
import 'lock.dart';
import 'practice.dart';
import 'profile.dart';
import 'sleep.dart';
import 'widgets.dart';

/// The More tab: the other areas, the lock choice and profile tools.
final class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = ProfileScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        SectionCard(
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sleep'),
                subtitle: const Text('diary, schedule, daylight'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openSleep(context),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Journal'),
                subtitle: const Text('mood, energy, symptoms, pain, illness'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openJournal(context),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Practices'),
                subtitle: const Text('breathing and other timed practices'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openPractices(context),
              ),
              for (final (title, subtitle) in [
                ('Goals & trials', 'goals, routines, trials, reviews'),
                ('Diet plan', 'programmes, cycles, reviews'),
                ('Gyms & equipment', 'gyms, instances, plates'),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: false,
                  title: Text(title),
                  subtitle: Text('$subtitle · coming to the app'),
                  trailing: const Icon(Icons.chevron_right),
                ),
            ],
          ),
        ),
        const LockSection(),
        BackupSection(
          recoveryDirectory: () async =>
              '${File(profile.path).parent.path}/recovery',
        ),
        SectionCard(
          title: 'Profile',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Muted(profile.path),
              if (kDebugMode) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => _loadDemo(context, profile),
                  child: const Text('Replace with demo data'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _loadDemo(BuildContext context, ProfileClient profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace with demo data?'),
        content: const Text(
          'This deletes everything in this profile and fills it with '
          'invented demonstration data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (confirmed == true) await profile.replaceWithDemo();
  }
}

final class _LockOption extends StatelessWidget {
  const _LockOption(
    this.title,
    this.subtitle, {
    this.selected = false,
    this.onTap,
  });
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: selected ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
          color: selected ? scheme.secondaryContainer : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? scheme.primary : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Muted(subtitle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The lock choice (D24): none, device unlock or passphrase.
final class LockSection extends StatefulWidget {
  const LockSection({super.key});

  @override
  State<LockSection> createState() => _LockSectionState();
}

final class _LockSectionState extends State<LockSection> {
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final profile = ProfileScope.of(context);
    final mode = profile.lock;
    return SectionCard(
      title: 'Lock',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LockOption(
            'No lock',
            'Data stays on this phone, unencrypted.',
            selected: mode == LockMode.none,
            onTap: busy ? null : () => _choose(LockMode.none),
          ),
          _LockOption(
            'Device unlock',
            "Fingerprint or screen lock. Key kept in the phone's keystore.",
            selected: mode == LockMode.device,
            onTap: busy ? null : () => _choose(LockMode.device),
          ),
          _LockOption(
            'Passphrase',
            'Asked when the app opens. Cannot be recovered if forgotten.',
            selected: mode == LockMode.passphrase,
            onTap: busy ? null : () => _choose(LockMode.passphrase),
          ),
          if (mode == LockMode.passphrase)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: busy ? null : () => _choose(LockMode.passphrase),
                child: const Text('Change passphrase'),
              ),
            ),
          if (mode != LockMode.none)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Expanded(child: Text('Lock again after leaving')),
                  DropdownButton<Duration>(
                    value: profile.relockAfter,
                    onChanged: busy
                        ? null
                        : (d) => d == null ? null : profile.setRelockAfter(d),
                    items: [
                      for (final d in relockChoices)
                        DropdownMenuItem(
                          value: d,
                          child: Text(
                            d == Duration.zero
                                ? 'Immediately'
                                : d.inHours >= 1
                                ? '${d.inHours} h'
                                : '${d.inMinutes} min',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Muted(
              'Locked profiles, their WAL and native backups are encrypted '
              '(ChaCha20-Poly1305). Without the key nothing can be recovered.',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _choose(LockMode next) async {
    final profile = ProfileScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    String? passphrase;
    switch (next) {
      case LockMode.passphrase:
        passphrase = await showDialog<String>(
          context: context,
          builder: (_) => const _PassphraseDialog(),
        );
        if (passphrase == null) return;
      case LockMode.device:
        if (!await _confirm(
          'Use device unlock?',
          'A random key is kept in this phone\'s keystore and released by '
              'your fingerprint or screen lock. If the screen lock is removed '
              'or the phone is reset, the profile cannot be opened: keep a '
              'backup or an encrypted export.',
          'Use device unlock',
        )) {
          return;
        }
      case LockMode.none:
        if (!await _confirm(
          'Remove the lock?',
          'The profile will be stored on this phone without encryption.',
          'Remove lock',
        )) {
          return;
        }
    }
    setState(() => busy = true);
    try {
      await profile.setLock(next, passphrase: passphrase);
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (next) {
            LockMode.none => 'The profile is no longer locked',
            LockMode.device => 'Locked with device unlock',
            LockMode.passphrase => 'Locked with a passphrase',
          }),
        ),
      );
    } on BodyTmiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;
}

final class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog();

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

final class _PassphraseDialogState extends State<_PassphraseDialog> {
  final first = TextEditingController();
  final second = TextEditingController();
  String? problem;

  @override
  void dispose() {
    first.dispose();
    second.dispose();
    super.dispose();
  }

  void _done() {
    if (first.text.runes.length < 8) {
      setState(() => problem = 'Use at least 8 characters.');
    } else if (first.text != second.text) {
      setState(() => problem = 'The passphrases differ.');
    } else {
      Navigator.pop(context, first.text);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Set a passphrase'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: first,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Passphrase'),
        ),
        TextField(
          controller: second,
          obscureText: true,
          onSubmitted: (_) => _done(),
          decoration: const InputDecoration(labelText: 'Repeat passphrase'),
        ),
        const SizedBox(height: 12),
        const Muted(
          'It is asked for whenever the app opens. Forgetting it loses '
          'the data: nobody can recover it.',
        ),
        if (problem != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              problem!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _done, child: const Text('Lock')),
    ],
  );
}
