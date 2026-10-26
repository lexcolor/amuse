import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/settings.dart';
import '../metadata/lyrics.dart';
import '../metadata/providers.dart';
import '../player/player_controller.dart';
import 'settings_dialog.dart';
import 'theme.dart';

class LyricsVisible extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final lyricsVisibleProvider = NotifierProvider<LyricsVisible, bool>(LyricsVisible.new);

/// Side panel showing the current track's lyrics; synced lyrics follow the
/// playback position and can be tapped to seek.
class LyricsPanel extends ConsumerWidget {
  const LyricsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(playerControllerProvider.select((s) => s.current));
    final text = Theme.of(context).textTheme;

    final onlineLyrics = ref.watch(settingsProvider.select((s) => s.onlineLyrics));
    final lyricsValue = track == null ? null : ref.watch(lyricsProvider(track));
    final fromLrclib = lyricsValue?.value?.source == LyricsSource.online;

    Widget body;
    if (track == null || lyricsValue == null) {
      body = const _Notice(icon: Icons.lyrics_outlined, text: 'Play something to see its lyrics');
    } else {
      body = lyricsValue.when(
            loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (_, _) => const _Notice(icon: Icons.cloud_off_rounded, text: 'Couldn\'t load lyrics'),
            data: (lyrics) {
              if (lyrics == null) {
                if (onlineLyrics) {
                  return const _Notice(icon: Icons.lyrics_outlined, text: 'No lyrics found for this song');
                }
                return _Notice(
                  icon: Icons.lyrics_outlined,
                  text: 'This file has no lyrics saved in it.\n'
                      'Online lyrics lookup is turned off.',
                  action: TextButton(
                    onPressed: () => showSettingsDialog(context),
                    child: const Text('Lyrics settings'),
                  ),
                );
              }
              if (lyrics.instrumental) {
                return const _Notice(icon: Icons.piano_rounded, text: 'Instrumental');
              }
              if (lyrics.isSynced) return _SyncedLyrics(key: ValueKey(track), lyrics: lyrics);
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 40),
                child: Text(lyrics.plain ?? '',
                    style: text.titleMedium?.copyWith(height: 1.7, color: AmuseColors.textSecondary)),
              );
            },
          );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        border: const Border(left: BorderSide(color: AmuseColors.outline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 16, 12),
            child: Row(children: [
              Expanded(child: Text('Lyrics', style: text.headlineSmall)),
              IconButton(
                onPressed: () => ref.read(lyricsVisibleProvider.notifier).toggle(),
                icon: const Icon(Icons.close_rounded, size: 20),
                color: AmuseColors.textSecondary,
                tooltip: 'Hide lyrics',
              ),
            ]),
          ),
          if (track != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
              child: _TrackCaption(track: track),
            ),
          Expanded(child: body),
          if (fromLrclib)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 16),
              child: Text('Lyrics from LRCLIB (lrclib.net)', style: text.bodySmall),
            ),
        ],
      ),
    );
  }
}

class _TrackCaption extends ConsumerWidget {
  const _TrackCaption({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.enriched(track);
    return Text(
      [t.title, t.artist].whereType<String>().join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

class _SyncedLyrics extends ConsumerStatefulWidget {
  const _SyncedLyrics({super.key, required this.lyrics});

  final Lyrics lyrics;

  @override
  ConsumerState<_SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends ConsumerState<_SyncedLyrics> {
  late final _keys = List.generate(widget.lyrics.synced.length, (_) => GlobalKey());
  int _current = -2;
  DateTime _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Highlight slightly early so the line lights up as it's sung, not after.
  static const _lead = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final current = widget.lyrics.lineAt(position + _lead);
    if (current != _current) {
      _current = current;
      WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
    }

    return NotificationListener<UserScrollNotification>(
      onNotification: (_) {
        _userScrolledAt = DateTime.now();
        return false;
      },
      child: ShaderMask(
        // Fade lines out at the top and bottom edges.
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
          stops: [0, 0.08, 0.85, 1],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 240),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < widget.lyrics.synced.length; i++)
                _Line(
                  key: _keys[i],
                  text: widget.lyrics.synced[i].text,
                  state: i == current ? _LinePhase.current : (i < current ? _LinePhase.past : _LinePhase.upcoming),
                  onTap: () => ref.read(playerControllerProvider.notifier).seek(widget.lyrics.synced[i].time),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _follow() {
    if (!mounted || _current < 0) return;
    // Let the user read ahead without being yanked back immediately.
    if (DateTime.now().difference(_userScrolledAt) < const Duration(seconds: 4)) return;
    final context = _keys[_current].currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.3,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }
}

enum _LinePhase { past, current, upcoming }

class _Line extends StatefulWidget {
  const _Line({super.key, required this.text, required this.state, required this.onTap});

  final String text;
  final _LinePhase state;
  final VoidCallback onTap;

  @override
  State<_Line> createState() => _LineViewState();
}

class _LineViewState extends State<_Line> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = switch (widget.state) {
      _LinePhase.current => AmuseColors.textPrimary,
      _LinePhase.past => AmuseColors.textSecondary.withValues(alpha: 0.55),
      _LinePhase.upcoming => AmuseColors.textSecondary.withValues(alpha: 0.8),
    };
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: _hover ? Colors.white.withValues(alpha: 0.05) : Colors.transparent,
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            style: TextStyle(
              fontFamily: DefaultTextStyle.of(context).style.fontFamily,
              fontSize: 22,
              height: 1.3,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: color,
            ),
            // Blank lines in LRC mark instrumental breaks.
            child: widget.text.isEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(Icons.music_note_rounded, size: 22, color: color),
                  )
                : Text(widget.text),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 36, color: AmuseColors.textMuted),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5)),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ]),
        ),
      );
}
