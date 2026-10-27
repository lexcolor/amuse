import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/player_controller.dart';
import '../radio/location.dart';
import '../radio/providers.dart';
import '../radio/radio_browser.dart';
import 'theme.dart';
import 'widgets/cover_art.dart';
import 'widgets/status_message.dart';

/// Live stations from the Radio Browser directory, near the user or in a
/// chosen country, with name search and genre filters.
class RadioView extends ConsumerWidget {
  const RadioView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(radioFilterProvider);
    final stations = ref.watch(visibleStationsProvider);
    final all = ref.watch(stationsProvider).value ?? const <RadioStation>[];
    final favorites = ref.watch(radioFavoritesProvider);
    final showFavorites = favorites.isNotEmpty && filter.query.isEmpty && filter.tag == null;
    final g = pageGutter(context);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(g, 36, g, 0),
          sliver: SliverToBoxAdapter(child: _Header(filter: filter, count: stations.value?.length)),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(g, 24, g, 0),
          sliver: SliverToBoxAdapter(child: _Controls()),
        ),
        if (all.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(g, 16, g, 0),
            sliver: SliverToBoxAdapter(child: _GenreChips(tags: topTags(all), selected: filter.tag)),
          ),
        if (showFavorites) ...[
          SliverPadding(
            padding: EdgeInsets.fromLTRB(g, 32, g, 12),
            sliver: SliverToBoxAdapter(child: _SectionTitle('Your stations')),
          ),
          SliverToBoxAdapter(child: _FavoritesStrip(stations: favorites)),
        ],
        if (showFavorites && stations.hasValue && stations.value!.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(g, 28, g, 0),
            sliver: SliverToBoxAdapter(
              child: _SectionTitle(filter.scope == RadioScope.nearMe ? 'Nearby' : 'Popular'),
            ),
          ),
        ...stations.when(
          loading: () => [
            const SliverRest(child: CircularProgressIndicator()),
          ],
          error: (e, _) => [
            SliverRest(
              child: StatusMessage(
                icon: Icons.wifi_off_rounded,
                title: 'Couldn\'t reach the radio directory',
                body: '$e',
                action: FilledButton.tonal(
                  onPressed: () => ref.invalidate(stationsProvider),
                  child: const Text('Try again'),
                ),
              ),
            ),
          ],
          data: (list) => [
            if (filter.needsLocation)
              const SliverRest(child: _LocatePrompt())
            else if (list.isEmpty)
              SliverRest(child: _NoStations(filter: filter))
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(g, 20, g, 40),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 20,
                    childAspectRatio: 0.74,
                  ),
                  itemCount: list.length,
                  itemBuilder: (context, i) => _StationCard(station: list[i], queue: list, index: i),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

void _play(WidgetRef ref, List<RadioStation> queue, int index) => ref
    .read(playerControllerProvider.notifier)
    .playQueue([for (final s in queue) s.toTrack()], index);

String _countryName(WidgetRef ref, String? code) {
  if (code == null) return 'Country';
  final countries = ref.watch(radioCountriesProvider).value ?? const [];
  for (final c in countries) {
    if (c.code == code) return c.name;
  }
  return code;
}

String formatDistance(double meters) =>
    meters < 1000 ? '${(meters / 100).round() * 100} m' : '${(meters / 1000).toStringAsFixed(meters < 10000 ? 1 : 0)} km';

class _Header extends ConsumerWidget {
  const _Header({required this.filter, required this.count});

  final RadioFilter filter;
  final int? count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final near = filter.scope == RadioScope.nearMe;
    final details = [
      if (count != null && !filter.needsLocation) '$count ${count == 1 ? 'station' : 'stations'}',
      if (near && !filter.needsLocation) 'within ${filter.radiusKm.round()} km',
      if (filter.query.isNotEmpty) 'matching “${filter.query}”',
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('LIVE RADIO', style: text.labelSmall?.copyWith(color: AmuseColors.textSecondary)),
      const SizedBox(height: 10),
      Text(
        near
            ? 'Stations near you'
            : filter.countryCode == null
                ? 'Popular stations'
                : 'Radio in ${_countryName(ref, filter.countryCode)}',
        style: text.displaySmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      if (details.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(details.join('  ·  '), style: text.bodyMedium),
      ],
    ]);
  }
}

class _Controls extends ConsumerStatefulWidget {
  const _Controls();

  @override
  ConsumerState<_Controls> createState() => _ControlsState();
}

class _ControlsState extends ConsumerState<_Controls> {
  final _search = TextEditingController();
  Timer? _debounce;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(radioFilterProvider).query;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450),
        () => ref.read(radioFilterProvider.notifier).setQuery(value));
  }

  Future<void> _nearMe() async {
    setState(() => _locating = true);
    try {
      await ref.read(radioFilterProvider.notifier).useNearMe();
    } on LocationUnavailable catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$e Pick a country instead, or check your privacy settings.'),
          behavior: SnackBarBehavior.floating,
          width: 520,
        ));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(radioFilterProvider);
    final controller = ref.read(radioFilterProvider.notifier);
    final near = filter.scope == RadioScope.nearMe;

    return Wrap(
      spacing: 10,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          height: 40,
          child: TextField(
            controller: _search,
            onChanged: _onSearch,
            onSubmitted: (v) {
              _debounce?.cancel();
              controller.setQuery(v);
            },
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search stations',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: filter.query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () {
                        _search.clear();
                        controller.setQuery('');
                      },
                    ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _Pill(
          label: 'Near me',
          icon: Icons.near_me_rounded,
          selected: near,
          busy: _locating,
          tooltip: near ? 'Update my location' : 'Find stations around you',
          onTap: _locating ? null : _nearMe,
        ),
        _Pill(
          label: _countryName(ref, filter.countryCode),
          icon: Icons.public_rounded,
          trailing: Icons.expand_more_rounded,
          selected: !near,
          onTap: () => _pickCountry(context, ref),
        ),
        if (near) ...[
          const SizedBox(width: 10),
          for (final km in const [10.0, 25.0, 50.0, 100.0])
            _Pill(
              label: '${km.round()} km',
              selected: filter.radiusKm == km,
              compact: true,
              onTap: () => controller.setRadius(km),
            ),
          const SizedBox(width: 10),
          _Pill(
            label: filter.nearestFirst ? 'Nearest first' : 'Most popular',
            icon: Icons.swap_vert_rounded,
            compact: true,
            selected: false,
            onTap: () => controller.setNearestFirst(!filter.nearestFirst),
          ),
        ],
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.trailing,
    this.tooltip,
    this.busy = false,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final IconData? trailing;
  final String? tooltip;
  final bool busy;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AmuseColors.background : AmuseColors.textPrimary;
    final pill = Material(
      color: selected ? AmuseColors.textPrimary : Colors.white.withValues(alpha: 0.06),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: compact ? 32 : 40,
          padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (busy)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: fg),
              )
            else if (icon != null)
              Icon(icon, size: compact ? 15 : 17, color: fg),
            if (icon != null || busy) const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                  color: fg,
                  fontSize: compact ? 12.5 : 13.5,
                  fontWeight: FontWeight.w600,
                )),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              Icon(trailing, size: 18, color: fg),
            ],
          ]),
        ),
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}

class _GenreChips extends ConsumerWidget {
  const _GenreChips({required this.tags, required this.selected});

  final List<String> tags;
  final String? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(radioFilterProvider.notifier);
    // Keep a selected genre visible even if it's not among the top ones.
    final shown = [?selected, for (final t in tags) if (t != selected) t];
    if (shown.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: [
      _Pill(label: 'All', compact: true, selected: selected == null, onTap: () => controller.setTag(null)),
      for (final t in shown)
        _Pill(
          label: t[0].toUpperCase() + t.substring(1),
          compact: true,
          selected: t == selected,
          onTap: () => controller.setTag(t == selected ? null : t),
        ),
    ]);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Text(title, style: Theme.of(context).textTheme.headlineSmall);
}

class _FavoritesStrip extends StatelessWidget {
  const _FavoritesStrip({required this.stations});

  final List<RadioStation> stations;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 222,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: pageGutter(context)),
        scrollDirection: Axis.horizontal,
        itemCount: stations.length,
        separatorBuilder: (_, _) => const SizedBox(width: 20),
        itemBuilder: (context, i) => SizedBox(
          width: 164,
          child: _StationCard(station: stations[i], queue: stations, index: i),
        ),
      ),
    );
  }
}

class _StationCard extends ConsumerStatefulWidget {
  const _StationCard({required this.station, required this.queue, required this.index});

  final RadioStation station;
  final List<RadioStation> queue;
  final int index;

  @override
  ConsumerState<_StationCard> createState() => _StationCardState();
}

class _StationCardState extends ConsumerState<_StationCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final station = widget.station;
    final track = station.toTrack();
    final text = Theme.of(context).textTheme;
    final current = ref.watch(playerControllerProvider.select((s) => s.current == track));
    final playing = current && (ref.watch(playingProvider).value ?? false);
    final favorite = ref.watch(radioFavoritesProvider.select((f) => f.contains(station)));
    final distance = station.distanceMeters;
    final subtitle = station.tags.isEmpty
        ? station.place ?? ''
        : station.tags.take(3).map((t) => t[0].toUpperCase() + t.substring(1)).join(', ');

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => current
            ? ref.read(playerControllerProvider.notifier).togglePlay()
            : _play(ref, widget.queue, widget.index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withValues(alpha: _hover ? 0.07 : current ? 0.05 : 0.025),
            border: Border.all(
              color: current ? AmuseColors.accent.withValues(alpha: 0.55) : Colors.transparent,
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                final size = c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight;
                return Stack(children: [
                  AnimatedScale(
                    scale: _hover ? 1.03 : 1,
                    duration: const Duration(milliseconds: 180),
                    child: CoverArt(track: track, size: size),
                  ),
                  if (_hover || current)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: _PlayBadge(playing: playing),
                    ),
                  if (_hover || favorite)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: IconButton(
                        tooltip: favorite ? 'Remove from your stations' : 'Add to your stations',
                        onPressed: () => ref.read(radioFavoritesProvider.notifier).toggle(station),
                        icon: Icon(favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 18),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.45),
                          foregroundColor: favorite ? const Color(0xFFFF7A8A) : Colors.white,
                          minimumSize: const Size(32, 32),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                ]);
              }),
            ),
            const SizedBox(height: 10),
            Text(station.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium?.copyWith(color: current ? AmuseColors.accent : null)),
            const SizedBox(height: 2),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall),
            const SizedBox(height: 6),
            Row(children: [
              if (station.quality != null) _Tag(station.quality!),
              const Spacer(),
              if (distance != null)
                Text(formatDistance(distance),
                    style: text.bodySmall?.copyWith(color: AmuseColors.textSecondary)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge({required this.playing});

  final bool playing;

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AmuseColors.textPrimary,
          boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: Icon(
          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 22,
          color: AmuseColors.background,
        ),
      );
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: AmuseColors.outline),
        ),
        child: Text(label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: AmuseColors.textMuted,
            )),
      );
}

class _LocatePrompt extends ConsumerWidget {
  const _LocatePrompt();

  @override
  Widget build(BuildContext context, WidgetRef ref) => const StatusMessage(
        icon: Icons.near_me_rounded,
        title: 'Find stations around you',
        body: 'Tap “Near me” to use your approximate location (rounded to about a kilometre).',
      );
}

class _NoStations extends ConsumerWidget {
  const _NoStations({required this.filter});

  final RadioFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final near = filter.scope == RadioScope.nearMe;
    final controller = ref.read(radioFilterProvider.notifier);
    return StatusMessage(
      icon: Icons.radio_rounded,
      title: filter.query.isNotEmpty ? 'No stations match “${filter.query}”' : 'No stations found',
      body: near
          ? 'Only stations that list their location show up near you, and many local '
              'stations don\'t. Try a wider radius, or browse your whole country.'
          : 'Try another search or country.',
      action: near && filter.radiusKm < 100
          ? FilledButton.tonal(
              onPressed: () => controller.setRadius(100),
              child: const Text('Search within 100 km'),
            )
          : null,
    );
  }
}

Future<void> _pickCountry(BuildContext context, WidgetRef ref) async {
  final code = await showDialog<String>(context: context, builder: (_) => const _CountryDialog());
  if (code != null) ref.read(radioFilterProvider.notifier).useCountry(code);
}

class _CountryDialog extends ConsumerStatefulWidget {
  const _CountryDialog();

  @override
  ConsumerState<_CountryDialog> createState() => _CountryDialogState();
}

class _CountryDialogState extends ConsumerState<_CountryDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final countries = ref.watch(radioCountriesProvider);
    final selected = ref.watch(radioFilterProvider.select((f) => f.countryCode));
    final text = Theme.of(context).textTheme;

    return Dialog(
      backgroundColor: AmuseColors.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: 420,
        height: 560,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
            child: Text('Choose a country', style: text.headlineSmall),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: countries.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Couldn\'t load countries: $e', style: text.bodyMedium),
                ),
              ),
              data: (all) {
                final list = [
                  for (final c in all)
                    if (_query.isEmpty || c.name.toLowerCase().contains(_query) || c.code.toLowerCase() == _query) c,
                ];
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final c = list[i];
                    final isSelected = c.code == selected;
                    return ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      selected: isSelected,
                      selectedTileColor: Colors.white.withValues(alpha: 0.06),
                      title: Text(c.name, style: text.titleMedium),
                      trailing: Text('${c.stationCount}', style: text.bodySmall),
                      onTap: () => Navigator.of(context).pop(c.code),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
