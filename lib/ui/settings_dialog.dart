import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings.dart';
import 'theme.dart';

Future<void> showSettingsDialog(BuildContext context) => showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => const _SettingsDialog(),
    );

class _SettingsDialog extends ConsumerWidget {
  const _SettingsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final text = Theme.of(context).textTheme;

    return Dialog(
      backgroundColor: AmuseColors.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AmuseColors.outline),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(child: Text('Settings', style: text.headlineSmall)),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: AmuseColors.textSecondary,
                ),
              ]),
              const SizedBox(height: 20),
              Text('LYRICS', style: text.labelSmall?.copyWith(color: AmuseColors.textMuted)),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Find lyrics online', style: text.titleMedium),
                        const SizedBox(height: 6),
                        Text(
                          'Lyrics saved inside your music files are always shown. When a song has '
                          'none, Amuse can look them up on LRCLIB (lrclib.net), a free, '
                          'community-maintained database.\n\n'
                          'Lyrics are copyrighted by their authors and publishers, and LRCLIB is '
                          'not a licensed lyrics provider. Turn this on only for your own '
                          'personal use.',
                          style: text.bodyMedium?.copyWith(height: 1.45),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Switch(
                    value: settings.onlineLyrics,
                    onChanged: ref.read(settingsProvider.notifier).setOnlineLyrics,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
