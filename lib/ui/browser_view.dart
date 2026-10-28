import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/providers.dart';
import '../core/settings.dart';
import '../sources/cloud_source.dart';
import '../metadata/providers.dart';
import '../player/player_controller.dart';
import '../sources/folders/locations.dart';
import '../sources/music_source.dart';
import 'add_location_dialog.dart';
import 'radio_view.dart';
import 'theme.dart';
import 'widgets/artwork.dart';
import 'widgets/cover_art.dart';
import 'widgets/status_message.dart';

class BrowserView extends ConsumerWidget {
  const BrowserView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final browse = ref.watch(browseProvider);
    final source = ref.watch(sourcesProvider)[browse.sourceId];

    if (browse.sourceId == 'radio') return const RadioView();
    if (source is CloudSource) {
      if (!source.auth.isConfigured) return _SetupNotice(source: source);
      final session = ref.watch(cloudSessionProvider(source.id));
      if (session.isLoading) return const Center(child: CircularProgressIndicator());
      if (session.hasError || session.value != true) return _Connect(source: source, error: session.error);
    }

    final listing = ref.watch(folderListingProvider((browse.sourceId, browse.folderId)));
    return listing.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => StatusMessage(
        icon: Icons.cloud_off_rounded,
        title: 'Couldn\'t load this folder',
        body: '$e',
        action: Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
          FilledButton.tonal(
            onPressed: () => ref.invalidate(folderListingProvider((browse.sourceId, browse.folderId))),
            child: const Text('Try again'),
          ),
          // A stale sign-in can fail in ways that look like any other error.
          if (source is CloudSource)
            OutlinedButton.icon(
              onPressed: () => ref.read(cloudSessionProvider(source.id).notifier).signIn(),
              icon: const Icon(Icons.sync_rounded, size: 18),
              label: const Text('Reconnect'),
            ),
        ]),
      ),
      data: (data) => _FolderView(browse: browse, listing: data),
    );
  }
}

class _FolderView extends ConsumerWidget {
  const _FolderView({required this.browse, required this.listing});

  final BrowseState browse;
  final FolderListing listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(sourcesProvider)[browse.sourceId]!;
    final controller = ref.read(playerControllerProvider.notifier);
    // Tags read from the files fill in as they arrive.
    final tracks = [for (final t in listing.tracks) ref.enriched(t)]..sort(compareTracks);
    final singleAlbum = tracks.isNotEmpty && tracks.every((t) => t.album == tracks.first.album);
    // The Folders root lists what the user added, so it can be edited.
    final editable = browse.sourceId == 'folders' && browse.path.isEmpty;
    final g = pageGutter(context);
    // Cloud drives open in their Music folder; say so if there isn't one.
    final musicFolderOnly = source is CloudSource &&
        browse.path.isEmpty &&
        ref.watch(settingsProvider.select((s) => s.musicFolderOnly));
    final locations = editable ? ref.watch(locationsProvider) : const <SavedLocation>[];
    final addButton = editable
        ? FilledButton.icon(
            onPressed: () => showAddLocationDialog(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add music'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16)),
          )
        : null;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(g, 28, g, 0),
          sliver: SliverToBoxAdapter(child: _Breadcrumbs(sourceName: source.displayName, path: browse.path)),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(g, 28, g, 32),
          sliver: SliverToBoxAdapter(
            child: _Hero(
              title: browse.path.isEmpty ? source.displayName : browse.path.last.name,
              listing: FolderListing(folders: listing.folders, tracks: tracks),
              onPlay: tracks.isEmpty ? null : () => controller.playQueue(tracks, 0),
              shuffle: listing.isEmpty || editable
                  ? null
                  : _ShuffleButton(
                      source: source,
                      listing: FolderListing(folders: listing.folders, tracks: tracks),
                    ),
              action: listing.isEmpty ? null : addButton,
            ),
          ),
        ),
        if (listing.isEmpty)
          SliverRest(
            child: editable
                ? StatusMessage(
                    icon: Icons.create_new_folder_rounded,
                    title: 'Bring your own music',
                    body: Theme.of(context).platform == TargetPlatform.android
                        ? 'Add a folder from this device or its SD card, or paste a web '
                            'address: a web folder, a song, or a radio stream.'
                        : 'Add a folder from this computer or a network share, or paste a web '
                            'address: a web folder, a song, or a radio stream.',
                    action: addButton,
                  )
                : musicFolderOnly
                    ? StatusMessage(
                        icon: Icons.library_music_outlined,
                        title: 'No Music folder yet',
                        body: 'Amuse opens ${source.displayName} in its Music folder. Create one and '
                            'put your albums in it, or browse the whole drive instead.',
                        action: FilledButton.icon(
                          onPressed: () => ref.read(settingsProvider.notifier).setMusicFolderOnly(false),
                          icon: const Icon(Icons.folder_open_rounded),
                          label: const Text('Show all folders'),
                        ),
                      )
                    : const StatusMessage(
                        icon: Icons.library_music_outlined,
                        title: 'Nothing playable here',
                        body: 'This folder has no sub-folders or audio files.',
                      ),
          ),
        if (listing.folders.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(g, 0, g, 32),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 190,
                mainAxisSpacing: 20,
                crossAxisSpacing: 20,
                childAspectRatio: 0.78,
              ),
              itemCount: listing.folders.length,
              itemBuilder: (context, i) {
                final folder = listing.folders[i];
                final web = locations.any((l) => l.uri == folder.id && l.kind == LocationKind.webFolder);
                return _FolderCard(
                  folder: folder,
                  icon: web ? Icons.public_rounded : Icons.folder_rounded,
                  onTap: () => ref.read(browseProvider.notifier).openFolder(folder),
                  shuffle: _ShuffleButton(
                    source: source,
                    listing: FolderListing(folders: [folder], tracks: const []),
                    compact: true,
                  ),
                  onRemove: editable ? () => ref.read(locationsProvider.notifier).remove(folder.id) : null,
                );
              },
            ),
          ),
        if (tracks.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(g - 12, 0, g - 12, 40),
            sliver: SliverList.builder(
              itemCount: tracks.length,
              itemBuilder: (context, i) => _TrackRow(
                track: tracks[i],
                index: i,
                showAlbum: !singleAlbum,
                onTap: () => controller.playQueue(tracks, i),
                onRemove: editable ? () => ref.read(locationsProvider.notifier).remove(tracks[i].id) : null,
              ),
            ),
          ),
      ],
    );
  }
}

class _Breadcrumbs extends ConsumerWidget {
  const _Breadcrumbs({required this.sourceName, required this.path});

  final String sourceName;
  final List<Folder> path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = [sourceName, ...path.map((f) => f.name)];
    final crumbs = <Widget>[];
    for (var i = 0; i < names.length; i++) {
      final last = i == names.length - 1;
      if (i > 0) {
        crumbs.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Icon(Icons.chevron_right_rounded, size: 16, color: AmuseColors.textMuted),
        ));
      }
      crumbs.add(InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: last ? null : () => ref.read(browseProvider.notifier).popTo(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(names[i],
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: last ? AmuseColors.textPrimary : AmuseColors.textSecondary,
              )),
        ),
      ));
    }
    return Row(children: [
      if (path.isNotEmpty) ...[
        _RoundIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: 'Back',
          onPressed: () => ref.read(browseProvider.notifier).popTo(path.length - 1),
        ),
        const SizedBox(width: 12),
      ],
      Expanded(child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: crumbs)),
      // Listings are kept for the session; cloud uploads can land later.
      IconButton(
        onPressed: () {
          final browse = ref.read(browseProvider);
          ref.invalidate(folderListingProvider((browse.sourceId, browse.folderId)));
        },
        tooltip: 'Refresh',
        icon: const Icon(Icons.refresh_rounded, size: 18),
        color: AmuseColors.textMuted,
      ),
      if (ref.watch(sourcesProvider)[ref.watch(browseProvider).sourceId] is CloudSource && isCompact(context))
        IconButton(
          onPressed: () => ref
              .read(cloudSessionProvider(ref.read(browseProvider).sourceId).notifier)
              .signOut(),
          tooltip: 'Disconnect',
          icon: const Icon(Icons.logout_rounded, size: 18),
          color: AmuseColors.textMuted,
        )
      else if (ref.watch(sourcesProvider)[ref.watch(browseProvider).sourceId] is CloudSource)
        TextButton.icon(
          onPressed: () => ref
              .read(cloudSessionProvider(ref.read(browseProvider).sourceId).notifier)
              .signOut(),
          icon: const Icon(Icons.logout_rounded, size: 16),
          label: const Text('Disconnect'),
          style: TextButton.styleFrom(foregroundColor: AmuseColors.textMuted),
        ),
    ]);
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.title, required this.listing, this.onPlay, this.shuffle, this.action});

  final String title;
  final FolderListing listing;
  final VoidCallback? onPlay;

  /// Shuffles everything in the folder, sub-folders included.
  final Widget? shuffle;

  /// An extra button after Play / Shuffle.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tracks = listing.tracks;
    final albums = tracks.map((t) => t.album).whereType<String>().toSet();
    final artists = tracks.map((t) => t.artist).whereType<String>().toSet();
    final isAlbum = tracks.isNotEmpty && albums.length == 1;
    final heading = isAlbum ? albums.single : title;
    final total = tracks.fold(Duration.zero, (sum, t) => sum + (t.duration ?? Duration.zero));

    final details = [
      if (artists.length == 1) artists.single else if (artists.length > 1) 'Various artists',
      if (listing.folders.isNotEmpty) '${listing.folders.length} folders',
      if (tracks.isNotEmpty) '${tracks.length} ${tracks.length == 1 ? 'track' : 'tracks'}',
      if (total > Duration.zero) formatDuration(total),
    ];

    final compact = isCompact(context);
    final artSize = compact ? 116.0 : 196.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (isAlbum)
          CoverArt(track: tracks.first, size: artSize)
        else
          Artwork(seed: heading, size: artSize, icon: tracks.isEmpty ? Icons.folder_rounded : null),
        SizedBox(width: compact ? 18 : 32),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isAlbum ? 'ALBUM' : 'FOLDER',
                  style: text.labelSmall?.copyWith(color: AmuseColors.textSecondary)),
              SizedBox(height: compact ? 6 : 10),
              Text(heading,
                  style: compact ? text.headlineSmall : text.displaySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              SizedBox(height: compact ? 6 : 12),
              Text(details.join('  ·  '), style: text.bodyMedium),
              if (onPlay != null || shuffle != null || action != null) ...[
                SizedBox(height: compact ? 14 : 22),
                Wrap(spacing: 0, runSpacing: 10, children: [
                  if (onPlay != null) ...[
                    FilledButton.icon(
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AmuseColors.textPrimary,
                        foregroundColor: AmuseColors.background,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  ?shuffle,
                  if (action != null) ...[
                    if (onPlay != null || shuffle != null) const SizedBox(width: 12),
                    action!,
                  ],
                ]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Plays everything in a folder and its sub-folders in random order.
class _ShuffleButton extends ConsumerStatefulWidget {
  const _ShuffleButton({required this.source, required this.listing, this.compact = false});

  final MusicSource source;
  final FolderListing listing;

  /// A round icon button, for folder cards.
  final bool compact;

  @override
  ConsumerState<_ShuffleButton> createState() => _ShuffleButtonState();
}

class _ShuffleButtonState extends ConsumerState<_ShuffleButton> {
  /// True until the first songs are found.
  bool _gathering = false;

  Future<void> _shuffle() async {
    setState(() => _gathering = true);
    final found = await ref.read(playerControllerProvider.notifier).playShuffled(
          tracksUnder(widget.source, widget.listing),
          onStarted: () {
            if (mounted) setState(() => _gathering = false);
          },
        );
    if (!mounted) return;
    setState(() => _gathering = false);
    if (!found) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No songs in this folder yet.'),
        behavior: SnackBarBehavior.floating,
        width: 320,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _gathering
        ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.shuffle_rounded, size: 18);
    if (widget.compact) {
      return IconButton(
        tooltip: 'Shuffle',
        onPressed: _gathering ? null : _shuffle,
        icon: icon,
        style: IconButton.styleFrom(
          backgroundColor: AmuseColors.textPrimary,
          foregroundColor: AmuseColors.background,
          disabledBackgroundColor: AmuseColors.textPrimary,
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: _gathering ? null : _shuffle,
      icon: icon,
      label: const Text('Shuffle'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AmuseColors.textPrimary,
        side: const BorderSide(color: Color(0x33FFFFFF)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
  }
}

class _FolderCard extends StatefulWidget {
  const _FolderCard({
    required this.folder,
    required this.onTap,
    this.icon = Icons.folder_rounded,
    this.onRemove,
    this.shuffle,
  });

  final Folder folder;
  final VoidCallback onTap;
  final IconData icon;

  /// Shown as a hover button when set.
  final Widget? shuffle;

  /// Shown as a hover button when set.
  final VoidCallback? onRemove;

  @override
  State<_FolderCard> createState() => _FolderCardState();
}

class _FolderCardState extends State<_FolderCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final count = widget.folder.childCount;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withValues(alpha: _hover ? 0.07 : 0.025),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => Stack(children: [
                    AnimatedScale(
                      scale: _hover ? 1.03 : 1,
                      duration: const Duration(milliseconds: 180),
                      child: Artwork(
                        seed: widget.folder.name,
                        size: min(c.maxWidth, c.maxHeight),
                        icon: widget.icon,
                      ),
                    ),
                    if (_hover && widget.onRemove != null)
                      Positioned(right: 4, top: 4, child: _RemoveButton(onPressed: widget.onRemove!)),
                    if (_hover && widget.shuffle != null)
                      Positioned(right: 8, bottom: 8, child: widget.shuffle!),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              Text(widget.folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium),
              if (count != null)
                Text('$count items', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackRow extends ConsumerStatefulWidget {
  const _TrackRow({
    required this.track,
    required this.index,
    required this.showAlbum,
    required this.onTap,
    this.onRemove,
  });

  final Track track;
  final int index;
  final bool showAlbum;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  ConsumerState<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends ConsumerState<_TrackRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final isCurrent = ref.watch(playerControllerProvider.select((s) => s.current == track));
    final text = Theme.of(context).textTheme;

    Widget leading;
    if (_hover) {
      leading = const Icon(Icons.play_arrow_rounded, size: 20);
    } else if (isCurrent) {
      leading = const Icon(Icons.graphic_eq_rounded, size: 18, color: AmuseColors.accent);
    } else {
      leading = Text('${track.trackNumber ?? widget.index + 1}', style: text.bodyMedium);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: _hover
                ? Colors.white.withValues(alpha: 0.06)
                : isCurrent
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.transparent,
          ),
          child: Row(children: [
            SizedBox(width: 32, child: Center(child: leading)),
            const SizedBox(width: 12),
            CoverArt(track: track, size: 38, radius: 6),
            const SizedBox(width: 14),
            Expanded(
              flex: 3,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(color: isCurrent ? AmuseColors.accent : null)),
                  if (track.artist != null)
                    Text(track.artist!, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall),
                ],
              ),
            ),
            if (widget.showAlbum && !isCompact(context))
              Expanded(
                flex: 2,
                child: Text(track.album ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
              ),
            if (track.format != null) _FormatChip(track.format!),
            SizedBox(
              width: isCompact(context) ? 52 : 64,
              child: _hover && widget.onRemove != null
                  ? Align(alignment: Alignment.centerRight, child: _RemoveButton(onPressed: widget.onRemove!))
                  : Text(track.isLive ? 'LIVE' : formatDuration(track.duration),
                      textAlign: TextAlign.right, style: text.bodyMedium),
            ),
          ]),
        ),
      ),
    );
  }
}

class _FormatChip extends StatelessWidget {
  const _FormatChip(this.format);

  final String format;

  @override
  Widget build(BuildContext context) {
    final lossless = const {'FLAC', 'ALAC', 'WAV', 'AIFF', 'AIF'}.contains(format);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: lossless ? AmuseColors.accent.withValues(alpha: 0.6) : AmuseColors.outline),
      ),
      child: Text(format,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: lossless ? AmuseColors.accent : AmuseColors.textMuted,
          )),
    );
  }
}

class _Connect extends ConsumerWidget {
  const _Connect({required this.source, this.error});

  final CloudSource source;
  final Object? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expired = error is SessionExpired;
    return StatusMessage(
      icon: expired ? Icons.cloud_sync_rounded : Icons.cloud_rounded,
      title: expired ? 'Reconnect your ${source.displayName}' : 'Connect your ${source.displayName}',
      body: expired
          ? 'Your ${source.displayName} sign-in has expired. Reconnect to keep listening.'
          : error != null
              ? 'Sign-in failed: $error'
              : 'Stream your music straight from the cloud. Amuse only asks for read access to your files.',
      action: FilledButton.icon(
        onPressed: () => ref.read(cloudSessionProvider(source.id).notifier).signIn(),
        icon: Icon(expired ? Icons.sync_rounded : Icons.login_rounded),
        label: Text(expired ? 'Reconnect' : source.signInLabel),
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16)),
      ),
    );
  }
}

class _SetupNotice extends StatelessWidget {
  const _SetupNotice({required this.source});

  final CloudSource source;

  @override
  Widget build(BuildContext context) {
    return StatusMessage(
      icon: Icons.key_rounded,
      title: '${source.displayName} isn\'t configured yet',
      body: 'Run the app with your OAuth client ID (see README):\n'
          'flutter run -d windows --dart-define=${source.clientIdDefine}=<your-client-id>\n\n'
          'Meanwhile, try playback with the Samples library.',
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onPressed, this.tooltip});

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 18),
        style: IconButton.styleFrom(
          backgroundColor: Colors.black.withValues(alpha: 0.3),
          foregroundColor: AmuseColors.textPrimary,
        ),
      );
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Remove from Folders',
        onPressed: onPressed,
        icon: const Icon(Icons.close_rounded, size: 16),
        style: IconButton.styleFrom(
          backgroundColor: Colors.black.withValues(alpha: 0.45),
          foregroundColor: Colors.white,
          minimumSize: const Size(30, 30),
          padding: EdgeInsets.zero,
        ),
      );
}
