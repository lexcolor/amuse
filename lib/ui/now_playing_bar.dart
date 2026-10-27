import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../metadata/providers.dart';
import '../player/player_controller.dart';
import 'lyrics_panel.dart';
import 'theme.dart';
import 'widgets/cover_art.dart';

class NowPlayingBar extends ConsumerWidget {
  const NowPlayingBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playerControllerProvider);
    final current = playback.current;
    final track = current == null ? null : ref.enriched(current);
    final live = track?.isLive ?? false;
    // Stations announce the song on air; until they do, show where they are.
    final onAir = live ? ref.watch(streamTitleProvider) : null;
    final text = Theme.of(context).textTheme;
    final subtitle = track == null
        ? null
        : playback.error ?? onAir ?? (live ? track.artist ?? 'Live radio' : track.subtitle);
    final subtitleStyle = text.bodySmall?.copyWith(
      color: playback.error != null ? Theme.of(context).colorScheme.error : null,
    );

    if (isCompact(context)) {
      return _CompactBar(track: track, subtitle: subtitle, subtitleStyle: subtitleStyle, live: live);
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          height: 92,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: AmuseColors.surface.withValues(alpha: 0.72),
            border: const Border(top: BorderSide(color: AmuseColors.outline)),
          ),
          child: Row(children: [
            // Track info
            Expanded(
              flex: 3,
              child: track == null
                  ? Text('Pick something to play', style: text.bodyMedium)
                  : Row(children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: CoverArt(key: ValueKey(track), track: track, size: 56, radius: 8),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(track.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleMedium),
                            const SizedBox(height: 2),
                            Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: subtitleStyle),
                          ],
                        ),
                      ),
                    ]),
            ),
            // Transport + progress
            Expanded(
              flex: 4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Transport(enabled: track != null),
                  const SizedBox(height: 2),
                  if (live) const _LiveIndicator() else _Progress(enabled: track != null),
                ],
              ),
            ),
            // Volume
            Expanded(
              flex: 3,
              child: Align(alignment: Alignment.centerRight, child: _Volume(lyrics: !live)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Phone layout: track and transport on one row, progress underneath, and no
/// volume (phones use their hardware buttons).
class _CompactBar extends StatelessWidget {
  const _CompactBar({required this.track, required this.subtitle, required this.subtitleStyle, required this.live});

  final Track? track;
  final String? subtitle;
  final TextStyle? subtitleStyle;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final track = this.track;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: EdgeInsets.fromLTRB(14, 10, 6, MediaQuery.paddingOf(context).bottom + 4),
          decoration: BoxDecoration(
            color: AmuseColors.surface.withValues(alpha: 0.72),
            border: const Border(top: BorderSide(color: AmuseColors.outline)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              if (track == null)
                Expanded(child: Text('Pick something to play', style: text.bodyMedium))
              else ...[
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: CoverArt(key: ValueKey(track), track: track, size: 46, radius: 7),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleMedium),
                    const SizedBox(height: 2),
                    Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: subtitleStyle),
                  ]),
                ),
              ],
              _Transport(enabled: track != null, compact: true),
            ]),
            if (track != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: live ? const _LiveIndicator() : const _Progress(enabled: true),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Transport extends ConsumerWidget {
  const _Transport({required this.enabled, this.compact = false});

  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playerControllerProvider.notifier);
    final playback = ref.watch(playerControllerProvider);
    final playing = ref.watch(playingProvider).value ?? false;
    final buffering = ref.watch(bufferingProvider).value ?? false;

    final gap = compact ? 0.0 : 10.0;
    return Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: enabled ? controller.previous : null,
          icon: const Icon(Icons.skip_previous_rounded, size: 26),
          color: AmuseColors.textSecondary,
        ),
        SizedBox(width: gap),
        SizedBox(
          width: 42,
          height: 42,
          child: Stack(alignment: Alignment.center, children: [
            IconButton.filled(
              onPressed: enabled ? controller.togglePlay : null,
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                child: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  key: ValueKey(playing),
                  size: 26,
                ),
              ),
              style: IconButton.styleFrom(
                backgroundColor: AmuseColors.textPrimary,
                foregroundColor: AmuseColors.background,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            if (enabled && buffering)
              const IgnorePointer(
                child: SizedBox.expand(
                  child: CircularProgressIndicator(strokeWidth: 2, color: AmuseColors.accent),
                ),
              ),
          ]),
        ),
        SizedBox(width: gap),
        IconButton(
          onPressed: enabled && playback.hasNext ? controller.next : null,
          icon: const Icon(Icons.skip_next_rounded, size: 26),
          color: AmuseColors.textSecondary,
        ),
      ],
    );
  }
}

class _Progress extends ConsumerStatefulWidget {
  const _Progress({required this.enabled});

  final bool enabled;

  @override
  ConsumerState<_Progress> createState() => _ProgressState();
}

class _ProgressState extends ConsumerState<_Progress> {
  /// Slider value while the user is dragging, so playback updates don't fight the thumb.
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final duration = ref.watch(durationProvider).value ?? Duration.zero;
    final maxMs = duration.inMilliseconds.toDouble();
    final valueMs = (_dragMs ?? position.inMilliseconds.toDouble()).clamp(0.0, maxMs > 0 ? maxMs : 0.0);
    final small = Theme.of(context).textTheme.bodySmall;

    return Row(children: [
      SizedBox(
        width: 44,
        child: Text(formatDuration(Duration(milliseconds: valueMs.round())),
            textAlign: TextAlign.right, style: small),
      ),
      Expanded(
        child: Slider(
          value: valueMs,
          max: maxMs > 0 ? maxMs : 1,
          onChanged: widget.enabled && maxMs > 0 ? (v) => setState(() => _dragMs = v) : null,
          onChangeEnd: (v) {
            ref.read(playerControllerProvider.notifier).seek(Duration(milliseconds: v.round()));
            setState(() => _dragMs = null);
          },
        ),
      ),
      SizedBox(width: 44, child: Text(formatDuration(duration), style: small)),
    ]);
  }
}

/// Stands in for the progress bar while a station plays.
class _LiveIndicator extends ConsumerWidget {
  const _LiveIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(playingProvider).value ?? false;
    return SizedBox(
      height: 28,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: playing ? const Color(0xFFFF5A6E) : AmuseColors.textMuted,
            boxShadow: playing
                ? const [BoxShadow(color: Color(0x88FF5A6E), blurRadius: 8)]
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Text('LIVE',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: playing ? AmuseColors.textPrimary : AmuseColors.textMuted,
                )),
      ]),
    );
  }
}

class _Volume extends ConsumerWidget {
  const _Volume({required this.lyrics});

  /// Radio has no lyrics, so the toggle hides while a station plays.
  final bool lyrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final volume = ref.watch(volumeProvider).value ?? 100;
    final controller = ref.read(playerControllerProvider.notifier);
    final lyricsOpen = ref.watch(lyricsVisibleProvider);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (lyrics) ...[
        IconButton(
          onPressed: () => ref.read(lyricsVisibleProvider.notifier).toggle(),
          tooltip: lyricsOpen ? 'Hide lyrics' : 'Show lyrics',
          icon: Icon(lyricsOpen ? Icons.lyrics_rounded : Icons.lyrics_outlined, size: 20),
          color: lyricsOpen ? AmuseColors.accent : AmuseColors.textSecondary,
        ),
        const SizedBox(width: 4),
      ],
      IconButton(
        onPressed: () => controller.setVolume(volume > 0 ? 0 : 100),
        icon: Icon(
          volume == 0
              ? Icons.volume_off_rounded
              : volume < 50
                  ? Icons.volume_down_rounded
                  : Icons.volume_up_rounded,
          size: 20,
        ),
        color: AmuseColors.textSecondary,
      ),
      SizedBox(
        width: 120,
        child: Slider(value: volume.clamp(0, 100), max: 100, onChanged: controller.setVolume),
      ),
    ]);
  }
}
