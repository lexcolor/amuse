// End-to-end check of the Folders source through the real providers: adds a
// local folder and a web folder the way the Add dialog does, lists them,
// reads tags, finds covers and plays (with a seek) from each.
// Run with:
//   flutter run -d windows -t tool/folders_probe.dart --dart-define=PROBE_DIR=<folder> --dart-define=PROBE_WEB=<url>
import 'dart:async';
import 'dart:io';

import 'package:amuse/core/models.dart';
import 'package:amuse/core/providers.dart';
import 'package:amuse/core/settings.dart';
import 'package:amuse/radio/providers.dart';
import 'package:amuse/metadata/providers.dart';
import 'package:amuse/player/player_controller.dart';
import 'package:amuse/sources/folders/locations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:shared_preferences/shared_preferences.dart';

const _dir = String.fromEnvironment('PROBE_DIR');
const _web = String.fromEnvironment('PROBE_WEB');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const SizedBox());

  // The app's real preferences, as main.dart opens them.
  final prefs = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(
        allowList: {...settingsKeys, ...radioPrefsKeys, ...locationsPrefsKeys}),
  );
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    cacheDirProvider.overrideWith((_) => Directory.systemTemp.createTempSync('amuse_probe_cache')),
  ]);
  final player = container.read(playerProvider);
  await player.setVolume(0);
  final source = container.read(sourcesProvider)['folders']!;
  var failed = false;

  void report(bool ok, String label, String details) {
    failed |= !ok;
    stdout.writeln('PROBE ${ok ? 'OK  ' : 'FAIL'} $label\n      $details');
  }

  /// Opens folders depth-first until one has tracks.
  Future<FolderListing> firstWithTracks(String folderId) async {
    final listing = await source.list(folderId);
    if (listing.tracks.isNotEmpty) return listing;
    for (final f in listing.folders) {
      final inner = await firstWithTracks(f.id);
      if (inner.tracks.isNotEmpty) return inner;
    }
    return listing;
  }

  Future<void> check(String input, {required bool seek}) async {
    try {
      final location = await inspectLocation(input, client: container.read(httpClientProvider));

      // Save it the way the Add dialog does and read the root back, through a
      // fresh container so the entry really came back from preferences.
      final alreadySaved = container.read(locationsProvider).any((l) => l.uri == location.uri);
      container.read(locationsProvider.notifier).add(location);
      final fresh = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      final root = await fresh.read(folderListingProvider(('folders', null)).future);
      final persisted = [...root.folders.map((f) => f.id), ...root.tracks.map((t) => t.id)].contains(location.uri);
      fresh.dispose();
      if (!alreadySaved) container.read(locationsProvider.notifier).remove(location.uri);
      report(persisted, '  saved and listed at the Folders root', 'persisted=$persisted');

      final listing = await firstWithTracks(location.uri);
      final tracks = [
        for (final t in listing.tracks.take(3)) await container.read(enrichedTrackProvider(t).future),
      ];
      final cover = tracks.isEmpty ? null : await container.read(coverProvider(tracks.first).future);
      report(tracks.isNotEmpty, '${location.kind.name}: ${location.name}',
          '${listing.tracks.length} tracks, e.g. ${tracks.map((t) => '${t.trackNumber ?? '-'} ${t.title} / ${t.artist} / ${t.album} / ${t.duration}').join(' | ')}; cover=${cover?.path}');

      for (final (i, t) in tracks.take(2).indexed) {
        await container.read(playerControllerProvider.notifier).playQueue(tracks, i);
        var position = await player.stream.position
            .firstWhere((p) => p > const Duration(seconds: 1))
            .timeout(const Duration(seconds: 30), onTimeout: () => Duration.zero);
        if (seek && position > Duration.zero) {
          await player.seek(const Duration(seconds: 60));
          position = await player.stream.position
              .firstWhere((p) => p > const Duration(seconds: 61))
              .timeout(const Duration(seconds: 30), onTimeout: () => Duration.zero);
        }
        final error = container.read(playerControllerProvider).error;
        report(position > Duration.zero && error == null, '  play ${t.title}',
            'position=$position format=${player.state.audioParams.format} rate=${player.state.audioParams.sampleRate} error=$error');
      }
    } catch (e) {
      report(false, input, '$e');
    }
  }

  if (_dir.isNotEmpty) await check(_dir, seek: true);
  if (_web.isNotEmpty) await check(_web, seek: false);

  container.dispose();
  exit(failed ? 1 : 0);
}
