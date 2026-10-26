import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/models.dart';
import '../core/providers.dart';
import '../core/settings.dart';
import 'lyrics.dart';
import 'metadata_repository.dart';

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final cacheDirProvider = FutureProvider<Directory>((ref) async {
  final support = await getApplicationSupportDirectory();
  return Directory('${support.path}${Platform.pathSeparator}cache');
});

final metadataRepositoryProvider = FutureProvider<MetadataRepository>((ref) async {
  return MetadataRepository(
    cacheDir: await ref.watch(cacheDirProvider.future),
    sources: ref.watch(sourcesProvider),
    client: ref.watch(httpClientProvider),
  );
});

/// [track] with gaps filled from the file's embedded tags. Tracks the source
/// already described fully, and live streams (which never end, so have no
/// header to read), are returned as-is without touching the network.
final enrichedTrackProvider = FutureProvider.family<Track, Track>((ref, track) async {
  if (track.hasBasicTags || track.isLive) return track;
  final repo = await ref.watch(metadataRepositoryProvider.future);
  try {
    return track.enrichedWith(await repo.tagsFor(track));
  } catch (_) {
    return track;
  }
});

extension EnrichedTrackRef on WidgetRef {
  /// The best-known version of [track], falling back to it while loading.
  Track enriched(Track track) => watch(enrichedTrackProvider(track)).value ?? track;
}

final coverProvider = FutureProvider.family<File?, Track>((ref, track) async {
  if (track.isLive) {
    final url = track.artworkUrl;
    if (url == null) return null;
    final repo = await ref.watch(metadataRepositoryProvider.future);
    final file = await repo.artworkFor(url);
    // Many stations only publish a tiny favicon; generated art looks better.
    return file != null && await _isAtLeast(file, 96) ? file : null;
  }
  final enriched = await ref.watch(enrichedTrackProvider(track).future);
  final repo = await ref.watch(metadataRepositoryProvider.future);
  return repo.coverFor(enriched);
});

/// Two accent colours sampled from the cover, for tinting the background.
final coverPaletteProvider = FutureProvider.family<(Color, Color)?, Track>((ref, track) async {
  final file = await ref.watch(coverProvider(track).future);
  if (file == null) return null;
  return paletteFromImage(await file.readAsBytes());
});

final lyricsProvider = FutureProvider.family<Lyrics?, Track>((ref, track) async {
  if (track.isLive) return null;
  final allowOnline = ref.watch(settingsProvider.select((s) => s.onlineLyrics));
  final enriched = await ref.watch(enrichedTrackProvider(track).future);
  final repo = await ref.watch(metadataRepositoryProvider.future);
  return repo.lyricsFor(enriched, allowOnline: allowOnline);
});

Future<bool> _isAtLeast(File file, int pixels) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(await file.readAsBytes());
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final ok = descriptor.width >= pixels && descriptor.height >= pixels;
    descriptor.dispose();
    buffer.dispose();
    return ok;
  } catch (_) {
    return false; // Not an image Flutter can decode (e.g. SVG or an HTML error page).
  }
}

/// Picks a vivid colour and a deep colour from a downscaled copy of the image.
Future<(Color, Color)?> paletteFromImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: 32,
    targetHeight: 32,
  );
  final image = (await codec.getNextFrame()).image;
  final data = await image.toByteData();
  image.dispose();
  if (data == null) return null;

  HSLColor? vivid, deep;
  var vividScore = -1.0, deepScore = -1.0;
  for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
    final hsl = HSLColor.fromColor(
        Color.fromARGB(255, data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2)));
    // Favour saturated mid-tones for the bright bloom, darker saturated tones for depth.
    final midness = 1 - (hsl.lightness - 0.55).abs() * 2;
    final v = hsl.saturation * midness;
    if (v > vividScore) {
      vividScore = v;
      vivid = hsl;
    }
    final d = hsl.saturation * (1 - (hsl.lightness - 0.3).abs() * 2);
    if (d > deepScore) {
      deepScore = d;
      deep = hsl;
    }
  }
  if (vivid == null || deep == null) return null;
  // Lift greyscale covers just enough to still give a tint.
  Color tune(HSLColor c, double lightness) =>
      c.withSaturation(c.saturation.clamp(0.25, 0.85)).withLightness(lightness).toColor();
  return (tune(vivid, 0.55), tune(deep, 0.28));
}
