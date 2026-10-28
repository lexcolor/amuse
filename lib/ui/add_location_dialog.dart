import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../metadata/providers.dart';
import '../platform/document_tree.dart';
import '../sources/folders/locations.dart';
import 'theme.dart';

bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Asks for a folder (picked or pasted) or a web address and saves it.
Future<void> showAddLocationDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _AddLocationDialog());

class _AddLocationDialog extends ConsumerStatefulWidget {
  const _AddLocationDialog();

  @override
  ConsumerState<_AddLocationDialog> createState() => _AddLocationDialogState();
}

class _AddLocationDialogState extends ConsumerState<_AddLocationDialog> {
  final _input = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    if (_android) return _pickDocumentFolder();
    final path = await getDirectoryPath(confirmButtonText: 'Add folder');
    if (path == null) return;
    _input.text = path;
    await _add();
  }

  /// Android only reaches shared storage and SD cards through folders the
  /// user grants in the system picker.
  Future<void> _pickDocumentFolder() async {
    setState(() => _error = null);
    try {
      final picked = await const DocumentTree().pickFolder();
      if (picked == null) return;
      ref.read(locationsProvider.notifier).add(
          SavedLocation(kind: LocationKind.folder, uri: picked.uri, name: picked.name));
      if (mounted) Navigator.of(context).pop();
    } on DocumentAccessException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _add() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final location = await inspectLocation(_input.text, client: ref.read(httpClientProvider));
      ref.read(locationsProvider.notifier).add(location);
      if (mounted) Navigator.of(context).pop();
    } on LocationException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: AmuseColors.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: 520,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add music', style: text.headlineSmall),
              const SizedBox(height: 8),
              Text(
                _android
                    ? 'Pick a folder on this device or its SD card, or paste a web address: '
                        'a web folder, a song, or a radio stream.'
                    : 'Pick a folder on this computer, or paste a path or web address: '
                        'a network share, a web folder, a song, or a radio stream.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _input,
                // On a phone the keyboard would cover the picker button.
                autofocus: !_android,
                enabled: !_busy,
                onSubmitted: (_) => _add(),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: _android ? 'https://…' : r'D:\Music   ·   \\nas\music   ·   https://…',
                  prefixIcon: const Icon(Icons.link_rounded, size: 18),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: _error == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(_error!,
                            style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
                      ),
              ),
              const SizedBox(height: 22),
              Row(children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _browse,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: Text(_android ? 'Pick folder…' : 'Browse…'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AmuseColors.textPrimary,
                    side: const BorderSide(color: Color(0x33FFFFFF)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _add,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
                  child: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Add'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
