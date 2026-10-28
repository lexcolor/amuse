import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/settings.dart';
import 'theme.dart';

Future<void> showSettingsDialog(BuildContext context) => showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => const _SettingsDialog(),
    );

/// Hosted with the web build (web/privacy.html, web/terms.html).
final _privacyUrl = Uri.parse('https://amuse.lexdes.com/privacy');
final _termsUrl = Uri.parse('https://amuse.lexdes.com/terms');

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
        child: SingleChildScrollView(
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
              Text('LIBRARY', style: text.labelSmall?.copyWith(color: AmuseColors.textMuted)),
              const SizedBox(height: 8),
              _SettingRow(
                title: 'Music folder only',
                body: 'OneDrive and Google Drive open straight into your Music folder, '
                    'whatever language its name is in, instead of listing everything in the account.',
                value: settings.musicFolderOnly,
                onChanged: ref.read(settingsProvider.notifier).setMusicFolderOnly,
              ),
              const SizedBox(height: 28),
              Text('LYRICS', style: text.labelSmall?.copyWith(color: AmuseColors.textMuted)),
              const SizedBox(height: 8),
              _SettingRow(
                title: 'Find lyrics online',
                body: 'Lyrics saved inside your music files are always shown. When a song has '
                    'none, Amuse can look them up on LRCLIB (lrclib.net), a free, '
                    'community-maintained database.\n\n'
                    'Lyrics are copyrighted by their authors and publishers, and LRCLIB is '
                    'not a licensed lyrics provider. Turn this on only for your own '
                    'personal use.',
                value: settings.onlineLyrics,
                onChanged: ref.read(settingsProvider.notifier).setOnlineLyrics,
              ),
              const SizedBox(height: 28),
              Text('ABOUT', style: text.labelSmall?.copyWith(color: AmuseColors.textMuted)),
              const SizedBox(height: 4),
              Wrap(spacing: 8, children: [
                TextButton(onPressed: () => launchUrl(_privacyUrl), child: const Text('Privacy policy')),
                TextButton(onPressed: () => launchUrl(_termsUrl), child: const Text('Terms of service')),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.title, required this.body, required this.value, required this.onChanged});

  final String title;
  final String body;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.titleMedium),
              const SizedBox(height: 6),
              Text(body, style: text.bodyMedium?.copyWith(height: 1.45)),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
