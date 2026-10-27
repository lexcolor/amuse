import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../metadata/providers.dart';
import '../player/player_controller.dart';
import 'browser_view.dart';
import 'lyrics_panel.dart';
import 'settings_dialog.dart';
import 'now_playing_bar.dart';
import 'theme.dart';

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(mediaSessionProvider);
    if (isCompact(context)) return const _CompactShell();
    return const Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _AmbientBackground()),
          Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Sidebar(),
                    Expanded(child: BrowserView()),
                    _LyricsSlot(),
                  ],
                ),
              ),
              NowPlayingBar(),
            ],
          ),
        ],
      ),
    );
  }
}

/// Phone layout: the sidebar moves into a drawer and the content takes the
/// full width.
class _CompactShell extends StatelessWidget {
  const _CompactShell();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        width: 280,
        backgroundColor: AmuseColors.surface,
        child: Builder(
          builder: (context) => SafeArea(
            child: _Sidebar(onNavigate: () => Navigator.of(context).pop()),
          ),
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _AmbientBackground()),
          Column(
            children: [
              SafeArea(
                bottom: false,
                child: Builder(
                  builder: (context) => Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                    child: Row(children: [
                      IconButton(
                        onPressed: () => Scaffold.of(context).openDrawer(),
                        tooltip: 'Menu',
                        icon: const Icon(Icons.menu_rounded),
                        color: AmuseColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      const _Logo(),
                    ]),
                  ),
                ),
              ),
              const Expanded(child: BrowserView()),
              const NowPlayingBar(),
            ],
          ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          gradient: const LinearGradient(colors: [Color(0xFFC9A6FF), Color(0xFF6A3FD8)]),
        ),
        child: const Icon(Icons.graphic_eq_rounded, size: 18, color: Colors.white),
      ),
      const SizedBox(width: 12),
      Text('Amuse', style: Theme.of(context).textTheme.headlineSmall),
    ]);
  }
}

/// Soft colour blooms tinted by the current track, cross-fading on change.
class _AmbientBackground extends ConsumerWidget {
  const _AmbientBackground();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(playerControllerProvider.select((s) => s.current));
    final coverPalette = track == null ? null : ref.watch(coverPaletteProvider(track)).value;
    final (light, dark) = track == null
        ? (AmuseColors.accent, const Color(0xFF3B1F8C))
        : coverPalette ?? artPalette(ref.enriched(track).artSeed);
    return TweenAnimationBuilder<double>(
      key: ValueKey((light, dark)),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90, tileMode: TileMode.decal),
        child: Stack(
          children: [
            _bloom(const Alignment(-1.1, -1.2), 620, light.withValues(alpha: 0.30 * t)),
            _bloom(const Alignment(1.2, -0.4), 520, dark.withValues(alpha: 0.55 * t)),
            _bloom(const Alignment(0.2, 1.4), 480, light.withValues(alpha: 0.14 * t)),
          ],
        ),
      ),
    );
  }

  Widget _bloom(Alignment alignment, double size, Color color) => Align(
        alignment: alignment,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      );
}

class _LyricsSlot extends ConsumerWidget {
  const _LyricsSlot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(lyricsVisibleProvider);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      width: visible ? 380 : 0,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: 380,
          maxWidth: 380,
          child: visible ? const LyricsPanel() : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({this.onNavigate});

  /// Set when shown in the phone drawer, to close it after picking a source.
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final browse = ref.watch(browseProvider);

    final sources = ref.watch(sourcesProvider);

    Widget item(String label, IconData icon, {String? sourceId, String? badge}) {
      if (sourceId != null && !sources.containsKey(sourceId)) return const SizedBox.shrink();
      final selected = sourceId != null && browse.sourceId == sourceId;
      return _SidebarItem(
        label: label,
        icon: icon,
        selected: selected,
        badge: badge,
        onTap: sourceId == null
            ? null
            : () {
                ref.read(browseProvider.notifier).openSource(sourceId);
                onNavigate?.call();
              },
      );
    }

    final inDrawer = onNavigate != null;
    return Container(
      width: inDrawer ? null : 232,
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
      decoration: inDrawer
          ? null
          : BoxDecoration(
              color: Colors.black.withValues(alpha: 0.22),
              border: const Border(right: BorderSide(color: AmuseColors.outline)),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 10, bottom: 32),
            child: Align(alignment: Alignment.centerLeft, child: _Logo()),
          ),
          _sectionLabel(context, 'LIBRARY'),
          item('OneDrive', Icons.cloud_rounded, sourceId: 'onedrive'),
          item('Google Drive', Icons.add_to_drive_rounded, sourceId: 'googledrive'),
          item('Folders', Icons.folder_rounded, sourceId: 'folders'),
          item('Samples', Icons.science_rounded, sourceId: 'demo'),
          const SizedBox(height: 24),
          _sectionLabel(context, 'DISCOVER'),
          item('Radio', Icons.radio_rounded, sourceId: 'radio'),
          const Spacer(),
          _SidebarItem(
            label: 'Settings',
            icon: Icons.settings_rounded,
            selected: false,
            onTap: () => showSettingsDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) => Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 8),
        child: Text(label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AmuseColors.textMuted)),
      );
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.selected,
    this.badge,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final String? badge;
  final VoidCallback? onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final color = widget.selected
        ? AmuseColors.textPrimary
        : enabled
            ? AmuseColors.textSecondary
            : AmuseColors.textMuted;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: widget.selected
                ? Colors.white.withValues(alpha: 0.09)
                : _hover && enabled
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.transparent,
          ),
          child: Row(children: [
            Icon(widget.icon, size: 19, color: widget.selected ? AmuseColors.accent : color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(widget.label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 14)),
            ),
            if (widget.badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: Colors.white.withValues(alpha: 0.06),
                ),
                child: Text(widget.badge!,
                    style: const TextStyle(fontSize: 10, color: AmuseColors.textMuted)),
              ),
          ]),
        ),
      ),
    );
  }
}
