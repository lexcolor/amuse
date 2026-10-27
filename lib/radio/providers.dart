import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/providers.dart';
import '../core/settings.dart';
import 'location.dart';
import 'radio_browser.dart';
import 'radio_source.dart';

const _filterKey = 'radio.filter';
const _favoritesKey = 'radio.favorites';
const radioPrefsKeys = {_filterKey, _favoritesKey};

enum RadioScope { nearMe, country }

/// Where to look for stations and how to narrow them down. Scope, country,
/// location and radius are remembered between runs; the rest isn't.
class RadioFilter {
  const RadioFilter({
    required this.scope,
    this.countryCode,
    this.location,
    this.radiusKm = 50,
    this.nearestFirst = false,
    this.query = '',
    this.tag,
  });

  factory RadioFilter.fromJson(Map<String, Object?> json) {
    final lat = json['lat'] as num?, lon = json['lon'] as num?;
    return RadioFilter(
      scope: json['scope'] == 'nearMe' ? RadioScope.nearMe : RadioScope.country,
      countryCode: json['country'] as String?,
      location: lat == null || lon == null ? null : GeoPoint(lat.toDouble(), lon.toDouble()),
      radiusKm: (json['radiusKm'] as num?)?.toDouble() ?? 50,
      nearestFirst: json['nearestFirst'] as bool? ?? false,
    );
  }

  final RadioScope scope;
  final String? countryCode;

  /// Last known position (already rounded to ~1 km).
  final GeoPoint? location;
  final double radiusKm;
  final bool nearestFirst;

  /// Station name search, sent to the directory.
  final String query;

  /// Genre filter, applied locally to the fetched stations.
  final String? tag;

  bool get needsLocation => scope == RadioScope.nearMe && location == null;

  RadioFilter copyWith({
    RadioScope? scope,
    String? countryCode,
    GeoPoint? location,
    double? radiusKm,
    bool? nearestFirst,
    String? query,
    String? Function()? tag,
  }) =>
      RadioFilter(
        scope: scope ?? this.scope,
        countryCode: countryCode ?? this.countryCode,
        location: location ?? this.location,
        radiusKm: radiusKm ?? this.radiusKm,
        nearestFirst: nearestFirst ?? this.nearestFirst,
        query: query ?? this.query,
        tag: tag == null ? this.tag : tag(),
      );

  Map<String, Object?> toJson() => {
        'scope': scope.name,
        'country': countryCode,
        'lat': location?.latitude,
        'lon': location?.longitude,
        'radiusKm': radiusKm,
        'nearestFirst': nearestFirst,
      };
}

/// "es_ES" â†’ "ES"; null when the locale names no country.
String? countryFromLocale(String localeName) {
  for (final part in localeName.split(RegExp(r'[_\-.@]')).skip(1)) {
    if (RegExp(r'^[A-Za-z]{2}$').hasMatch(part)) return part.toUpperCase();
  }
  return null;
}

class RadioFilterController extends Notifier<RadioFilter> {
  SharedPreferencesWithCache get _prefs => ref.read(sharedPreferencesProvider);

  @override
  RadioFilter build() {
    final saved = _prefs.getString(_filterKey);
    if (saved != null) {
      try {
        return RadioFilter.fromJson(jsonDecode(saved) as Map<String, Object?>);
      } on FormatException {
        // Fall through to defaults.
      }
    }
    // Start with the user's own country, from the system locale.
    return RadioFilter(scope: RadioScope.country, countryCode: countryFromLocale(kIsWeb ? PlatformDispatcher.instance.locale.toString() : Platform.localeName));
  }

  void useCountry(String code) =>
      _save(state.copyWith(scope: RadioScope.country, countryCode: code, tag: () => null));

  /// Switches to stations near the device, locating it first. Throws
  /// [LocationUnavailable] (and keeps the current filter) if that fails.
  Future<void> useNearMe({Future<GeoPoint> Function() locate = currentLocation}) async {
    final here = await locate();
    _save(state.copyWith(scope: RadioScope.nearMe, location: here, tag: () => null));
  }

  void setRadius(double km) => _save(state.copyWith(radiusKm: km));

  void setNearestFirst(bool nearest) => _save(state.copyWith(nearestFirst: nearest));

  void setQuery(String query) => state = state.copyWith(query: query, tag: () => null);

  void setTag(String? tag) => state = state.copyWith(tag: () => tag);

  void _save(RadioFilter filter) {
    state = filter;
    _prefs.setString(_filterKey, jsonEncode(filter.toJson()));
  }
}

final radioFilterProvider =
    NotifierProvider<RadioFilterController, RadioFilter>(RadioFilterController.new);

final radioBrowserProvider =
    Provider<RadioBrowser>((ref) => (ref.watch(sourcesProvider)['radio']! as RadioSource).browser);

/// Stations for the current scope and search, before the local genre filter.
final stationsProvider = FutureProvider<List<RadioStation>>((ref) async {
  final filter = ref.watch(radioFilterProvider.select((f) => (
        f.scope,
        f.countryCode,
        f.location,
        f.radiusKm,
        f.query,
      )));
  final (scope, countryCode, location, radiusKm, query) = filter;
  if (scope == RadioScope.nearMe && location == null) return const [];
  return ref.watch(radioBrowserProvider).search(
        near: scope == RadioScope.nearMe ? location : null,
        radiusKm: radiusKm,
        countryCode: scope == RadioScope.country ? countryCode : null,
        name: query,
      );
});

/// [stationsProvider] narrowed by genre and sorted for display.
final visibleStationsProvider = Provider<AsyncValue<List<RadioStation>>>((ref) {
  final tag = ref.watch(radioFilterProvider.select((f) => f.tag));
  final nearest = ref.watch(radioFilterProvider
      .select((f) => f.scope == RadioScope.nearMe && f.nearestFirst));
  return ref.watch(stationsProvider).whenData((stations) {
    final list = [
      for (final s in stations)
        if (tag == null || s.tags.contains(tag)) s,
    ];
    if (nearest) {
      list.sort((a, b) => (a.distanceMeters ?? double.infinity).compareTo(b.distanceMeters ?? double.infinity));
    }
    return list;
  });
});

/// The genres that best split the current results, most common first.
List<String> topTags(List<RadioStation> stations, {int count = 10}) {
  final counts = <String, int>{};
  for (final s in stations) {
    for (final t in s.tags.toSet()) {
      if (t.length > 1 && t.length <= 18) counts[t] = (counts[t] ?? 0) + 1;
    }
  }
  // A tag every station has (e.g. the country) doesn't help filtering.
  counts.removeWhere((_, n) => n < 2 || n == stations.length);
  final sorted = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  return sorted.take(count).toList();
}

final radioCountriesProvider =
    FutureProvider<List<RadioCountry>>((ref) => ref.watch(radioBrowserProvider).countries());

/// Stations the user starred, stored locally with everything needed to play them.
class RadioFavorites extends Notifier<List<RadioStation>> {
  SharedPreferencesWithCache get _prefs => ref.read(sharedPreferencesProvider);

  @override
  List<RadioStation> build() {
    final saved = _prefs.getStringList(_favoritesKey) ?? const [];
    final stations = <RadioStation>[];
    for (final s in saved) {
      try {
        stations.add(RadioStation.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {
        // Skip a corrupt entry rather than losing the rest.
      }
    }
    return stations;
  }

  void toggle(RadioStation station) {
    state = state.contains(station)
        ? [for (final s in state) if (s != station) s]
        : [...state, station];
    _prefs.setStringList(_favoritesKey, [for (final s in state) jsonEncode(s.toJson())]);
  }
}

final radioFavoritesProvider =
    NotifierProvider<RadioFavorites, List<RadioStation>>(RadioFavorites.new);
