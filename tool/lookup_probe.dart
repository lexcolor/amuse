// Live check of the online metadata services. Run with:
//   dart run tool/lookup_probe.dart
import 'dart:io';

import 'package:amuse/core/models.dart';
import 'package:amuse/metadata/metadata_repository.dart';
import 'package:amuse/metadata/online_lookup.dart';
import 'package:amuse/sources/demo_source.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final client = http.Client();
  final lookup = OnlineLookup(client);

  const albums = [
    ('Radiohead', 'OK Computer'),
    ('Miles Davis', 'Kind of Blue (Legacy Edition)'),
    ('Soda Stereo', 'Canción Animal'),
    ('Nobody Real', 'An Album That Does Not Exist 9431'),
  ];
  for (final (artist, album) in albums) {
    stdout.writeln('cover  $artist / $album -> ${await lookup.findCoverUrl(artist: artist, album: album)}');
  }

  const songs = [
    ('Karma Police', 'Radiohead', 'OK Computer', Duration(seconds: 264)),
    ('De Música Ligera', 'Soda Stereo', 'Canción Animal', null),
    ('So What', 'Miles Davis', 'Kind of Blue', Duration(seconds: 562)),
  ];
  for (final (title, artist, album, duration) in songs) {
    final l = await lookup.findLyrics(title: title, artist: artist, album: album, duration: duration);
    stdout.writeln('lyrics $artist / $title -> '
        '${l == null ? 'none' : 'synced=${l.synced.length} lines, instrumental=${l.instrumental}, '
            'first="${l.synced.isEmpty ? l.plain?.split('\n').first : l.synced.first.text}"'}');
  }
  // Full repository chain: stream a real file's header, then fall back online.
  final cache = Directory.systemTemp.createTempSync('amuse_probe');
  final repo = MetadataRepository(cacheDir: cache, sources: {'demo': DemoSource()}, client: client);
  const track = Track(
    id: 'https://filesamples.com/samples/audio/flac/sample1.flac',
    sourceId: 'demo',
    title: 'Karma Police',
    artist: 'Radiohead',
    album: 'OK Computer',
  );
  final watch = Stopwatch()..start();
  final tags = await repo.tagsFor(track);
  stdout.writeln('repo   tags of a 12 MB FLAC in ${watch.elapsedMilliseconds} ms: duration=${tags.duration}');
  final cover = await repo.coverFor(track);
  stdout.writeln('repo   cover -> ${cover?.path} (${cover?.lengthSync()} bytes)');
  final lyrics = await repo.lyricsFor(track, duration: const Duration(seconds: 264), allowOnline: true);
  stdout.writeln('repo   lyrics -> ${lyrics?.synced.length} synced lines');
  watch.reset();
  await repo.coverFor(track);
  await MetadataRepository(cacheDir: cache, sources: const {}, client: client).lyricsFor(track, allowOnline: true);
  stdout.writeln('repo   cached lookups in ${watch.elapsedMilliseconds} ms');
  cache.deleteSync(recursive: true);
  client.close();
}
