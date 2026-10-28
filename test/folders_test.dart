import 'dart:io';

import 'package:amuse/core/models.dart';
import 'package:amuse/platform/document_tree.dart';
import 'package:amuse/sources/folders/folders_source.dart';
import 'package:amuse/sources/folders/locations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Trimmed copies of real index pages.
const _apacheIndex = '''
<html><head><title>Index of /music/Kind of Blue</title></head><body>
<h1>Index of /music/Kind of Blue</h1>
<table>
<tr><th><a href="?C=N;O=D">Name</a></th><th><a href="?C=M;O=A">Last modified</a></th></tr>
<tr><td><a href="/music/">Parent Directory</a></td></tr>
<tr><td><a href="Bonus%20Tracks/">Bonus Tracks/</a></td></tr>
<tr><td><a href="01%20-%20So%20What.flac">01 - So What.flac</a></td></tr>
<tr><td><a href="02%20-%20Freddie%20Freeloader.mp3">02 - Freddie Freeloader.mp3</a></td></tr>
<tr><td><a href="cover.jpg">cover.jpg</a></td></tr>
<tr><td><a href="https://elsewhere.example/x.mp3">mirror</a></td></tr>
</table></body></html>''';

const _nginxIndex = '''
<html><head><title>Index of /pub/</title></head><body>
<h1>Index of /pub/</h1><hr><pre><a href="../">../</a>
<a href="Live%20%26%20Loud/">Live &amp; Loud/</a>     01-Jan-2026 10:00    -
<a href="track.ogg">track.ogg</a>     01-Jan-2026 10:00    12345
<a href="deep/inner/x.mp3">x.mp3</a>
</pre><hr></body></html>''';

class _FakeDocuments extends DocumentTree {
  const _FakeDocuments(this.folders);

  final Map<String, List<DocumentEntry>> folders;

  @override
  Future<List<DocumentEntry>> list(String folderUri) async => folders[folderUri]!;
}

void main() {
  group('FoldersSource', () {
    late Directory dir;

    setUp(() {
      // Spaces and accents, like real music folders.
      dir = Directory.systemTemp.createTempSync('Música de prueba ');
      Directory('${dir.path}/Disco 2').createSync();
      Directory('${dir.path}/.cache').createSync();
      for (final name in ['02 - Dos.mp3', '01 - Uno.flac', 'Cover.JPG', 'notes.txt', '.hidden.mp3']) {
        File('${dir.path}/$name').writeAsBytesSync(const [0]);
      }
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('lists sub-folders and audio files, with the folder cover', () async {
      final listing = await FoldersSource(() => const []).list(dir.path);
      expect(listing.folders.map((f) => f.name), ['Disco 2']);
      expect(listing.tracks.map((t) => (t.title, t.trackNumber, t.format)), [
        ('Uno', 1, 'FLAC'),
        ('Dos', 2, 'MP3'),
      ]);
      final cover = Uri.parse(listing.tracks.first.artworkUrl!);
      expect(File.fromUri(cover).existsSync(), isTrue);
      expect(cover.pathSegments.last, 'Cover.JPG');

      // Nested folders are addressed by their full path.
      final inner = await FoldersSource(() => const []).list(listing.folders.single.id);
      expect(inner.isEmpty, isTrue);
    });

    test('root shows saved folders and links', () async {
      final listing = await FoldersSource(() => [
            SavedLocation(kind: LocationKind.folder, uri: dir.path, name: 'Música'),
            const SavedLocation(kind: LocationKind.webFolder, uri: 'https://host.example/music/', name: 'music'),
            const SavedLocation(
                kind: LocationKind.link, uri: 'https://radio.example/live', name: 'Radio X', isLive: true),
          ]).list(null);
      expect(listing.folders.map((f) => f.name), ['Música', 'music']);
      expect(listing.tracks.single.isLive, isTrue);
      expect(listing.tracks.single.title, 'Radio X');
    });

    test('a missing folder gives a readable error', () async {
      expect(FoldersSource(() => const []).list('${dir.path}/nope'), throwsA(isA<FileSystemException>()));
    });

    test('resolves paths, file links and web links', () async {
      final source = FoldersSource(() => const []);
      final path = '${dir.path}${Platform.pathSeparator}01 - Uno.flac';
      Future<Uri> uri(String id) async =>
          (await source.resolve(Track(id: id, sourceId: 'folders', title: 'x'))).uri;
      expect((await uri(path)).toFilePath(), path);
      expect((await uri(Uri.file(path).toString())).toFilePath(), path);
      expect((await uri('https://host.example/a b.mp3')).toString(), 'https://host.example/a%20b.mp3');
    });

    test('lists a web folder', () async {
      final source = FoldersSource(() => const [],
          client: MockClient((r) async => http.Response(_apacheIndex, 200, headers: {'content-type': 'text/html'})));
      final listing = await source.list('https://host.example/music/Kind%20of%20Blue');
      expect(listing.folders.map((f) => (f.name, f.id)),
          [('Bonus Tracks', 'https://host.example/music/Kind%20of%20Blue/Bonus%20Tracks/')]);
      expect(listing.tracks.map((t) => (t.title, t.trackNumber)), [('So What', 1), ('Freddie Freeloader', 2)]);
      expect(listing.tracks.first.artworkUrl, 'https://host.example/music/Kind%20of%20Blue/cover.jpg');
    });
  });

  test('lists an Android document folder and plays its content URIs', () async {
    const tree = 'content://com.android.externalstorage.documents/tree/1A2B-3C4D%3AMusic';
    String doc(String path) => '$tree/document/1A2B-3C4D%3AMusic%2F${Uri.encodeComponent(path)}';
    final source = FoldersSource(() => const [], documents: _FakeDocuments({
      tree: [
        DocumentEntry(uri: doc('Disco 2'), name: 'Disco 2', isFolder: true),
        DocumentEntry(uri: doc('02 - Dos.mp3'), name: '02 - Dos.mp3', isFolder: false),
        DocumentEntry(uri: doc('01 - Uno.flac'), name: '01 - Uno.flac', isFolder: false),
        DocumentEntry(uri: doc('01 - Uno.mp3'), name: '01 - Uno.mp3', isFolder: false),
        DocumentEntry(uri: doc('folder.jpg'), name: 'folder.jpg', isFolder: false),
        DocumentEntry(uri: doc('.thumbnails'), name: '.thumbnails', isFolder: true),
      ],
    }));

    final listing = await source.list(tree);
    expect(listing.folders.map((f) => (f.name, f.id)), [('Disco 2', doc('Disco 2'))]);
    expect(listing.tracks.map((t) => (t.title, t.format)), [('Uno', 'FLAC'), ('Dos', 'MP3')]);
    expect(listing.tracks.first.artworkUrl, doc('folder.jpg'));

    final stream = await source.resolve(listing.tracks.first);
    expect(stream.uri.toString(), doc('01 - Uno.flac'));
  });

  test('same song in several formats is listed once, best copy kept', () {
    Track t(String id, String format) => Track(id: id, sourceId: 'folders', title: id, format: format);
    final kept = preferredFormats([
      t('https://ia.example/item/d1t01.mp3', 'MP3'),
      t('https://ia.example/item/d1t01.flac', 'FLAC'),
      t('https://ia.example/item/d1t01.ogg', 'OGG'),
      t('https://ia.example/item/d1t02.mp3', 'MP3'),
      t(r'C:\Music\100% Hits.mp3', 'MP3'),
    ]);
    expect(kept.map((t) => t.id), [
      'https://ia.example/item/d1t01.flac',
      'https://ia.example/item/d1t02.mp3',
      r'C:\Music\100% Hits.mp3',
    ]);
  });

  test('parseWebIndex keeps direct children only (nginx)', () {
    final index = parseWebIndex(_nginxIndex, Uri.parse('http://nas.local/pub/'));
    expect(index.folders.map((e) => e.name), ['Live & Loud']);
    expect(index.files.map((e) => e.name), ['track.ogg']);
  });

  group('inspectLocation', () {
    test('local folder, quoted as Windows "Copy as path" does', () async {
      final dir = Directory.systemTemp.createTempSync('Mi música');
      addTearDown(() => dir.deleteSync(recursive: true));
      final loc = await inspectLocation(' "${dir.path}${Platform.pathSeparator}" ');
      expect(loc.kind, LocationKind.folder);
      expect(loc.uri, dir.path);
      expect(loc.name, dir.path.split(Platform.pathSeparator).last);
    });

    test('local audio file becomes a link; other files are refused', () async {
      final dir = Directory.systemTemp.createTempSync('amuse');
      addTearDown(() => dir.deleteSync(recursive: true));
      final song = File('${dir.path}${Platform.pathSeparator}Song.mp3')..writeAsBytesSync(const [0]);
      final text = File('${dir.path}/a.txt')..writeAsBytesSync(const [0]);
      final loc = await inspectLocation(song.path);
      expect((loc.kind, loc.name, loc.isLive), (LocationKind.link, 'Song', false));
      expect(Uri.parse(loc.uri).toFilePath(), song.path);
      expect(inspectLocation(text.path), throwsA(isA<LocationException>()));
      expect(inspectLocation('${dir.path}/missing'), throwsA(isA<LocationException>()));
    });

    Future<SavedLocation> web(String url, int status, Map<String, String> headers, {String body = ''}) =>
        inspectLocation(url,
            client: MockClient((_) async => http.Response(body, status, headers: headers)));

    test('web addresses are classified by what the server sends', () async {
      final folder = await web('https://host.example/music/', 200, {'content-type': 'text/html'});
      expect((folder.kind, folder.name), (LocationKind.webFolder, 'music'));

      final song = await web('https://host.example/a/Song%20One.flac', 200,
          {'content-type': 'audio/flac', 'content-length': '0'});
      expect((song.kind, song.name, song.isLive), (LocationKind.link, 'Song One', false));

      final radio = await web('https://stream.example/live', 200,
          {'content-type': 'audio/mpeg', 'icy-name': 'Radio Example'});
      expect((radio.kind, radio.name, radio.isLive), (LocationKind.link, 'Radio Example', true));

      final pls = await web('https://stream.example/listen.pls', 200,
          {'content-type': 'audio/x-scpls', 'content-length': '0'});
      expect(pls.isLive, isTrue);

      expect(web('https://host.example/private/', 403, const {}), throwsA(isA<LocationException>()));
    });
  });
}
