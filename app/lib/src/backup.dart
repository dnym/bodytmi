import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import 'profile.dart';
import 'widgets.dart';

/// Moving export files in and out of the app.
abstract interface class FileTransfer {
  /// Offers [bytes] for saving as [name]; false when cancelled.
  Future<bool> save(String name, Uint8List bytes);

  /// A chosen file's bytes; null when cancelled.
  Future<Uint8List?> pick();
}

/// Android's system "Save as" and file picker (Storage Access Framework):
/// the user decides where exports go, including cloud folders they chose.
final class SystemFileTransfer implements FileTransfer {
  const SystemFileTransfer();

  @override
  Future<bool> save(String name, Uint8List bytes) async =>
      await FilePicker.saveFile(
        fileName: name,
        bytes: bytes,
        mimeType: 'application/json',
        dialogTitle: 'Save export',
      ) !=
      null;

  @override
  Future<Uint8List?> pick() async {
    final file = await FilePicker.pickFile(dialogTitle: 'Choose an export');
    return file?.xFile.readAsBytes();
  }
}

/// Where export files go and come from; tests replace it.
FileTransfer fileTransfer = const SystemFileTransfer();

/// The largest export file read for a restore (an encrypted export of the
/// 64 MiB logical limit stays below it).
const _maxExportBytes = 96 * 1024 * 1024;

/// More → Backup and export: a full logical export, plain or encrypted with
/// its own passphrase, and restoring the profile from one.
final class BackupSection extends StatefulWidget {
  const BackupSection({super.key, required this.recoveryDirectory});

  /// Where the safety backup of the current profile goes before a restore.
  final Future<String> Function() recoveryDirectory;

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

final class _BackupSectionState extends State<BackupSection> {
  bool busy = false;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Backup and export',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Muted(
          'A full export of everything in this profile, saved where you '
          'choose. Encrypt it with its own passphrase, or save plain JSON '
          'that any app can read.',
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: busy ? null : _export,
          icon: const Icon(Icons.upload_file),
          label: const Text('Export…'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy ? null : _restore,
          icon: const Icon(Icons.restore),
          label: const Text('Restore from export…'),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
      ],
    ),
  );

  void _show(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } on BodyTmiException catch (e) {
      if (mounted) _show(e.message);
    } on FileSystemException catch (e) {
      if (mounted) _show('The file could not be read or written: ${e.message}');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _export() async {
    final profile = ProfileScope.of(context);
    final choice = await showDialog<_ExportChoice>(
      context: context,
      builder: (_) => const _ExportDialog(),
    );
    if (choice == null) return;
    await _run(() async {
      final result = await profile.exportArchive(passphrase: choice.passphrase);
      final now = DateTime.now();
      final stamp =
          '${now.year}${_two(now.month)}${_two(now.day)}-'
          '${_two(now.hour)}${_two(now.minute)}';
      final saved = await fileTransfer.save(
        'bodytmi-export-$stamp${choice.passphrase == null ? '' : '-encrypted'}.json',
        result.bytes,
      );
      if (saved && mounted) {
        _show(
          '${choice.passphrase == null ? 'Plain' : 'Encrypted'} export saved '
          '(${(result.bytes.length / 1024).ceil()} KB)',
        );
      }
    });
  }

  Future<void> _restore() async {
    final profile = ProfileScope.of(context);
    final bytes = await fileTransfer.pick();
    if (bytes == null || !mounted) return;
    await _run(() async {
      if (bytes.length > _maxExportBytes) {
        invalid('The file is larger than any BodyTMI export.');
      }
      final Object? json;
      try {
        json = jsonDecode(utf8.decode(bytes));
      } on FormatException {
        invalid('This is not a BodyTMI export file.');
      }
      String? passphrase;
      if (EncryptedFile.recognises(json)) {
        passphrase = await showDialog<String>(
          context: context,
          builder: (_) => const _AskPassphraseDialog(),
        );
        if (passphrase == null) return;
      }
      final dir = await Directory.systemTemp.createTemp('bodytmi-restore-');
      try {
        final file = File('${dir.path}/export.json');
        await file.writeAsBytes(bytes, flush: true);
        final summary = await profile.inspectExport(
          file.path,
          passphrase: passphrase,
        );
        if (!mounted) return;
        if (!await _confirmRestore(summary)) return;
        final now = DateTime.now();
        final recovery =
            '${await widget.recoveryDirectory()}/before-restore-'
            '${now.year}${_two(now.month)}${_two(now.day)}-'
            '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
        await profile.restoreExport(
          file.path,
          passphrase: passphrase,
          recoveryDestination: recovery,
        );
        if (mounted) {
          _show(
            'Restored. The previous profile was kept as a recovery backup.',
          );
        }
      } finally {
        await dir.delete(recursive: true);
      }
    });
  }

  Future<bool> _confirmRestore(Map<String, Object?> summary) async {
    final records = (summary['records'] as Map?) ?? const {};
    final counts = [
      for (final e in records.entries)
        if (e.value is int && (e.value as int) > 0)
          '${e.value} ${_words('${e.key}')}',
    ];
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Replace this profile?'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Everything in this profile is replaced by the export. '
                    'A recovery backup of the current profile is kept in the '
                    "app's storage. The profile keeps its own lock.",
                  ),
                  const SizedBox(height: 12),
                  Muted(
                    counts.isEmpty
                        ? 'The export is empty.'
                        : 'The export holds ${counts.join(', ')}.',
                  ),
                ],
              ),
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
        ) ==
        true;
  }
}

String _two(int v) => v.toString().padLeft(2, '0');

final class _ExportChoice {
  const _ExportChoice(this.passphrase);
  final String? passphrase;
}

final class _ExportDialog extends StatefulWidget {
  const _ExportDialog();

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

final class _ExportDialogState extends State<_ExportDialog> {
  bool encrypt = true;
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
    if (!encrypt) {
      Navigator.pop(context, const _ExportChoice(null));
    } else if (first.text.runes.length < 8) {
      setState(() => problem = 'Use at least 8 characters.');
    } else if (first.text != second.text) {
      setState(() => problem = 'The passphrases differ.');
    } else {
      Navigator.pop(context, _ExportChoice(first.text));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Export'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Encrypt with a passphrase'),
            value: encrypt,
            onChanged: (v) => setState(() {
              encrypt = v;
              problem = null;
            }),
          ),
          if (encrypt) ...[
            TextField(
              controller: first,
              obscureText: true,
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
              'This passphrase belongs to the file only; it can differ from '
              'the profile lock. Without it the file cannot be opened.',
            ),
          ] else
            const Muted(
              'A plain export is readable by anyone who gets the file, '
              'including cloud services it is saved to.',
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
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _done, child: const Text('Export')),
    ],
  );
}

final class _AskPassphraseDialog extends StatefulWidget {
  const _AskPassphraseDialog();

  @override
  State<_AskPassphraseDialog> createState() => _AskPassphraseDialogState();
}

final class _AskPassphraseDialogState extends State<_AskPassphraseDialog> {
  final text = TextEditingController();

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Encrypted export'),
    content: TextField(
      controller: text,
      obscureText: true,
      autofocus: true,
      onSubmitted: (_) => Navigator.pop(context, text.text),
      decoration: const InputDecoration(labelText: "The export's passphrase"),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, text.text),
        child: const Text('Open'),
      ),
    ],
  );
}

/// `diaryEntries` → `diary entries`.
String _words(String key) =>
    key.replaceAllMapped(RegExp('[A-Z]'), (m) => ' ${m[0]!.toLowerCase()}');
