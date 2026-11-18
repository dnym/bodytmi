import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'profile.dart';
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
              for (final (title, subtitle) in [
                ('Sleep', 'diary, schedule, daylight'),
                ('Journal', 'mood, energy, symptoms'),
                ('Practices', 'box breathing, playlists'),
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
        const SectionCard(
          title: 'Lock',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LockOption(
                'No lock',
                'Data stays on this phone, unencrypted.',
                selected: true,
              ),
              _LockOption(
                'Device unlock',
                "Fingerprint or screen lock. Key kept in the phone's keystore.",
              ),
              _LockOption(
                'Passphrase',
                'Asked when the app opens. Cannot be recovered if forgotten.',
              ),
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Muted('Choosing a lock arrives in a later version.'),
              ),
            ],
          ),
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
  const _LockOption(this.title, this.subtitle, {this.selected = false});
  final String title;
  final String subtitle;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
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
    );
  }
}
