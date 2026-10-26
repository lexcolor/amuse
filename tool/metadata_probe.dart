// Runs the real metadata providers inside Flutter (app cache directory,
// cover lookup, palette extraction, lyrics). Run with:
//   flutter run -d windows -t tool/metadata_probe.dart
import 'dart:io';

import 'package:amuse/core/models.dart';
import 'package:amuse/core/settings.dart';
import 'package:amuse/metadata/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox());

  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [settingsProvider.overrideWith(_OnlineLyrics.new)],
  );
  const track = Track(
    id: 'https://filesamples.com/samples/audio/flac/sample1.flac',
    sourceId: 'demo',
    title: 'Karma Police',
    artist: 'Radiohead',
    album: 'OK Computer',
    // The sample file is ~2 min; lyrics matching needs the real song length.
    duration: Duration(seconds: 264),
  );

  var ok = true;
  try {
    final watch = Stopwatch()..start();
    final cacheDir = await container.read(cacheDirProvider.future);
    final enriched = await container.read(enrichedTrackProvider(track).future);
    final cover = await container.read(coverProvider(track).future);
    final palette = await container.read(coverPaletteProvider(track).future);
    final lyrics = await container.read(lyricsProvider(track).future);
    ok = cover != null && palette != null && (lyrics?.isSynced ?? false);
    stdout.writeln('PROBE ${ok ? 'OK  ' : 'FAIL'} in ${watch.elapsedMilliseconds} ms\n'
        '      cache=${cacheDir.path}\n'
        '      duration=${enriched.duration} cover=${cover?.path}\n'
        '      palette=$palette lyrics=${lyrics?.synced.length} synced lines');
  } catch (e, s) {
    ok = false;
    stdout.writeln('PROBE FAIL $e\n$s');
  }
  container.dispose();
  exit(ok ? 0 : 1);
}

class _OnlineLyrics extends SettingsController {
  @override
  AppSettings build() => const AppSettings(onlineLyrics: true);
}
