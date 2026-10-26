import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:amuse/core/models.dart';
import 'package:amuse/metadata/header_reader.dart';
import 'package:amuse/metadata/lyrics.dart';
import 'package:amuse/metadata/metadata_repository.dart';
import 'package:amuse/metadata/online_lookup.dart';
import 'package:amuse/metadata/tag_parser.dart';
import 'package:amuse/sources/demo_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _cover = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 1, 2, 3, 4, 5]);

void main() {
  group('FLAC', () {
    test('reads STREAMINFO duration, Vorbis comments and front cover', () {
      final tags = parseTags(_flac());
      expect(tags.title, 'So What');
      expect(tags.artist, 'Miles Davis');
      expect(tags.albumArtist, 'Miles Davis');
      expect(tags.album, 'Kind of Blue');
      expect(tags.trackNumber, 1);
      expect(tags.year, 1959);
      expect(tags.duration, const Duration(minutes: 9, seconds: 22));
      expect(tags.picture?.mimeType, 'image/png');
      expect(tags.picture?.bytes, _cover);
    });

    test('reads tags from a local file', () async {
      final dir = Directory.systemTemp.createTempSync('amuse ñ local');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}01 - So What.flac')
        ..writeAsBytesSync([..._flac(), ...List.filled(4096, 0)]);
      final tags = await readLocalTags(file);
      expect((tags.title, tags.album), ('So What', 'Kind of Blue'));
    });

    test('asks for more data until the needed blocks are present', () {
      final full = _flac();
      expect(() => parseTags(Uint8List.sublistView(full, 0, 50)), throwsA(isA<NeedMoreData>()));
    });

    test('truncated input returns what was read', () {
      final full = _flac();
      // Cut inside the PICTURE block: text tags survive, picture doesn't.
      final tags = parseTags(Uint8List.sublistView(full, 0, full.length - 3), truncated: true);
      expect(tags.title, 'So What');
      expect(tags.picture, isNull);
    });

    test('FLAC with a prepended ID3 tag prefers native comments', () {
      final data = Uint8List.fromList([..._id3(3, {'TIT2': 'Wrong', 'TCON': 'Jazz'}), ..._flac()]);
      expect(parseTags(data).title, 'So What');
    });
  });

  group('ID3v2', () {
    test('v2.3 with UTF-16 text, APIC and USLT', () {
      final tags = parseTags(Uint8List.fromList([
        ..._id3(3, {
          'TIT2': 'Karma Police',
          'TPE1': 'Radiohead',
          'TALB': 'OK Computer',
          'TRCK': '6/12',
          'TYER': '1997',
        }, utf16: true, picture: _cover, lyrics: 'Karma police\nArrest this man'),
        ...List.filled(2000, 0xff), // audio frames
      ]));
      expect(tags.title, 'Karma Police');
      expect(tags.artist, 'Radiohead');
      expect(tags.album, 'OK Computer');
      expect(tags.trackNumber, 6);
      expect(tags.year, 1997);
      expect(tags.lyrics, 'Karma police\nArrest this man');
      expect(tags.picture?.bytes, _cover);
      expect(tags.picture?.mimeType, 'image/jpeg');
    });

    test('v2.4 with UTF-8, syncsafe sizes and multi-value text', () {
      final tags = parseTags(Uint8List.fromList([
        ..._id3(4, {
          'TIT2': 'Ñandú — 東京',
          'TPE1': 'Artist A\u0000Artist B',
          'TDRC': '2021-05-03',
          'TLEN': '215000',
        }),
        ...List.filled(64, 0xff), // audio frames
      ]));
      expect(tags.title, 'Ñandú — 東京');
      expect(tags.artist, 'Artist A');
      expect(tags.year, 2021);
      expect(tags.duration, const Duration(minutes: 3, seconds: 35));
    });

    test('file without tags yields empty tags', () {
      final tags = parseTags(Uint8List.fromList(List.filled(64, 0xff)));
      expect(tags.title, isNull);
    });
  });

  group('readRemoteTags', () {
    test('stops downloading once tags are parsed, even if Range is ignored', () async {
      final file = Uint8List.fromList([..._flac(), ...List.filled(8 * 1024 * 1024, 0)]);
      var sentBytes = 0;
      final client = MockClient.streaming((request, _) async {
        // Behaves like filesamples.com: always sends the whole file with 200.
        Stream<List<int>> chunks() async* {
          for (var i = 0; i < file.length; i += 16 * 1024) {
            final chunk = file.sublist(i, (i + 16 * 1024).clamp(0, file.length));
            sentBytes += chunk.length;
            yield chunk;
          }
        }

        return http.StreamedResponse(chunks(), 200);
      });

      final tags = await readRemoteTags(client, PlayableStream(Uri.parse('https://x/a.flac')));
      expect(tags.album, 'Kind of Blue');
      expect(tags.picture, isNotNull);
      expect(sentBytes, lessThan(64 * 1024));
    });

    test('throws on HTTP errors', () async {
      final client = MockClient((_) async => http.Response('gone', 403));
      expect(readRemoteTags(client, PlayableStream(Uri.parse('https://x/a.mp3'))),
          throwsA(isA<http.ClientException>()));
    });
  });

  group('lyrics', () {
    test('parses LRC and finds the current line', () {
      final lyrics = Lyrics(synced: parseLrc('[ar:Radiohead]\n[00:26.78]Karma police\n'
          '[00:31.00]Arrest this man\n[01:02.5][02:10.00]Chorus'));
      expect(lyrics.synced.map((l) => l.text), ['Karma police', 'Arrest this man', 'Chorus', 'Chorus']);
      expect(lyrics.synced.first.time, const Duration(seconds: 26, milliseconds: 780));
      expect(lyrics.synced[2].time, const Duration(minutes: 1, seconds: 2, milliseconds: 500));
      expect(lyrics.lineAt(const Duration(seconds: 10)), -1);
      expect(lyrics.lineAt(const Duration(seconds: 30)), 0);
      expect(lyrics.lineAt(const Duration(minutes: 5)), 3);
    });

    test('round-trips through JSON', () {
      final lyrics = Lyrics(synced: parseLrc('[00:01.00]One\n[00:02.50]Two'), plain: 'One\nTwo');
      final back = Lyrics.fromJson(jsonDecode(jsonEncode(lyrics.toJson())) as Map<String, Object?>);
      expect(back.synced.map((l) => l.time), lyrics.synced.map((l) => l.time));
      expect(back.plain, 'One\nTwo');
    });
  });

  group('MetadataRepository', () {
    late Directory cache;
    var fileRequests = 0;
    var onlineRequests = 0;

    MetadataRepository repo() => MetadataRepository(
          cacheDir: cache,
          sources: {'demo': DemoSource()},
          client: MockClient((request) async {
            if (request.url.path.endsWith('.flac')) {
              fileRequests++;
              return http.Response.bytes(_flac(), 200);
            }
            onlineRequests++;
            return http.Response('', 404); // every online lookup misses
          }),
        );

    setUp(() {
      cache = Directory.systemTemp.createTempSync('amuse_test');
      fileRequests = 0;
      onlineRequests = 0;
    });
    tearDown(() => cache.deleteSync(recursive: true));

    const track = Track(id: 'https://x/so-what.flac', sourceId: 'demo', title: 'so-what');

    test('concurrent lookups complete and share one download', () async {
      final r = repo();
      final results = await Future.wait([r.tagsFor(track), r.tagsFor(track)])
          .timeout(const Duration(seconds: 5));
      expect(results.map((t) => t.title), ['So What', 'So What']);
      expect(fileRequests, 1);
    });

    test('embedded picture becomes the album cover; results survive restarts', () async {
      final enriched = track.enrichedWith(await repo().tagsFor(track));
      final cover = await repo().coverFor(enriched).timeout(const Duration(seconds: 5));
      expect(cover?.readAsBytesSync(), _cover);
      expect(fileRequests, 1, reason: 'second repository reads tags from the disk cache');
    });

    test('online lyrics are opt-in', () async {
      final enriched = track.enrichedWith(await repo().tagsFor(track));
      expect(await repo().lyricsFor(enriched), isNull);
      expect(onlineRequests, 0, reason: 'LRCLIB must not be contacted while the setting is off');
      expect(Directory('${cache.path}/lyrics').existsSync(), isFalse);
    });

    test('missing online lyrics are remembered', () async {
      // The app passes tracks enriched with their file tags (artist etc.).
      final enriched = track.enrichedWith(await repo().tagsFor(track));
      expect(await repo().lyricsFor(enriched, allowOnline: true), isNull);
      final afterFirst = onlineRequests;
      expect(afterFirst, greaterThan(0));
      expect(await repo().lyricsFor(enriched, allowOnline: true), isNull);
      expect(onlineRequests, afterFirst);
      expect(fileRequests, 1);
    });
  });

  test('normalizeName ignores edition suffixes, articles and punctuation', () {
    expect(normalizeName('The Dark Side of the Moon (2011 Remaster)'),
        normalizeName('Dark Side Of The Moon'));
    expect(normalizeName('Simon & Garfunkel'), normalizeName('Simon and Garfunkel'));
  });
}

// ------------------------------------------------------------ fixtures ---

Uint8List _flac() {
  final out = BytesBuilder()..add(ascii.encode('fLaC'));
  void block(int type, List<int> body, {bool last = false}) {
    out
      ..addByte((last ? 0x80 : 0) | type)
      ..add([body.length >> 16 & 0xff, body.length >> 8 & 0xff, body.length & 0xff])
      ..add(body);
  }

  // STREAMINFO: 44.1 kHz, stereo, 16-bit, 562 s of samples.
  const rate = 44100, samples = 44100 * 562;
  final info = Uint8List(34);
  info[10] = rate >> 12 & 0xff;
  info[11] = rate >> 4 & 0xff;
  info[12] = (rate & 0x0f) << 4 | (1 << 1) | 0; // channels-1 = 1, bps high bit
  info[13] = 0xf0 | (samples >> 32 & 0x0f); // bps low bits = 15 (16-bit)
  info[14] = samples >> 24 & 0xff;
  info[15] = samples >> 16 & 0xff;
  info[16] = samples >> 8 & 0xff;
  info[17] = samples & 0xff;
  block(0, info);

  block(1, Uint8List(1024)); // padding

  final comments = [
    'TITLE=So What', 'artist=Miles Davis', 'ALBUMARTIST=Miles Davis', 'ALBUM=Kind of Blue',
    'TRACKNUMBER=1/5', 'DATE=1959-08-17',
  ];
  final vc = BytesBuilder()
    ..add(_le32(6))
    ..add(ascii.encode('fixtur'))
    ..add(_le32(comments.length));
  for (final c in comments) {
    final bytes = utf8.encode(c);
    vc
      ..add(_le32(bytes.length))
      ..add(bytes);
  }
  block(4, vc.takeBytes());

  final mime = ascii.encode('image/png');
  final pic = BytesBuilder()
    ..add(_be32(3))
    ..add(_be32(mime.length))
    ..add(mime)
    ..add(_be32(0))
    ..add(Uint8List(16))
    ..add(_be32(_cover.length))
    ..add(_cover);
  block(6, pic.takeBytes(), last: true);
  return out.takeBytes();
}

List<int> _id3(int major, Map<String, String> frames,
    {bool utf16 = false, Uint8List? picture, String? lyrics}) {
  final body = BytesBuilder();
  void frame(String id, List<int> data) {
    body
      ..add(ascii.encode(id))
      ..add(major == 4 ? _syncsafe(data.length) : _be32(data.length))
      ..add([0, 0])
      ..add(data);
  }

  List<int> encode(String s) => utf16
      ? [1, 0xff, 0xfe, for (final u in s.codeUnits) ...[u & 0xff, u >> 8]]
      : [major == 4 ? 3 : 0, ...(major == 4 ? utf8.encode(s) : latin1.encode(s))];

  frames.forEach((id, value) => frame(id, encode(value)));
  if (lyrics != null) {
    frame('USLT', [0, ...ascii.encode('eng'), 0, ...latin1.encode(lyrics)]);
  }
  if (picture != null) {
    frame('APIC', [0, ...ascii.encode('image/jpeg'), 0, 3, ...ascii.encode('cover'), 0, ...picture]);
  }
  body.add(Uint8List(32)); // padding

  final tag = body.takeBytes();
  return [...ascii.encode('ID3'), major, 0, 0, ..._syncsafe(tag.length), ...tag];
}

List<int> _le32(int v) => [v & 0xff, v >> 8 & 0xff, v >> 16 & 0xff, v >> 24 & 0xff];
List<int> _be32(int v) => [v >> 24 & 0xff, v >> 16 & 0xff, v >> 8 & 0xff, v & 0xff];
List<int> _syncsafe(int v) => [v >> 21 & 0x7f, v >> 14 & 0x7f, v >> 7 & 0x7f, v & 0x7f];
