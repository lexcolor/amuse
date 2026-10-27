import 'dart:convert';

import 'package:amuse/core/models.dart';
import 'package:amuse/sources/auth/loopback_oauth.dart';
import 'package:amuse/sources/cloud_source.dart';
import 'package:amuse/sources/google_drive/google_drive_source.dart';
import 'package:amuse/sources/music_source.dart';
import 'package:amuse/sources/onedrive/onedrive_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('titleFromFileName', () {
    expect(titleFromFileName('03 - So What.flac'), (number: 3, title: 'So What'));
    expect(titleFromFileName('3. So What.mp3'), (number: 3, title: 'So What'));
    expect(titleFromFileName('12 Blue in Green.mp3'), (number: 12, title: 'Blue in Green'));
    expect(titleFromFileName('So What.flac'), (number: null, title: 'So What'));
    expect(titleFromFileName('1979.mp3'), (number: null, title: '1979'));
  });

  group('GoogleDriveSource', () {
    final requests = <http.Request>[];

    GoogleDriveSource source(List<Map<String, Object?>> pages) {
      var page = 0;
      return GoogleDriveSource(
        _FakeAuth(),
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode(pages[page++]), 200);
        }),
      );
    }

    setUp(requests.clear);

    test('lists folders, audio files and shortcuts across pages', () async {
      final listing = await source([
        {
          'nextPageToken': 'p2',
          'files': [
            {'id': 'f1', 'name': 'Kind of Blue', 'mimeType': 'application/vnd.google-apps.folder'},
            {'id': 'a1', 'name': '02 - Freddie Freeloader.flac', 'mimeType': 'audio/flac'},
            {'id': 'x1', 'name': 'cover.jpg', 'mimeType': 'image/jpeg'},
          ],
        },
        {
          'files': [
            {
              'id': 's1',
              'name': 'Shortcut to Jazz',
              'mimeType': 'application/vnd.google-apps.shortcut',
              'shortcutDetails': {'targetId': 'f2', 'targetMimeType': 'application/vnd.google-apps.folder'},
            },
            {'id': 'a2', 'name': '01 - So What.mp3', 'mimeType': 'audio/mpeg'},
            {'id': 'a3', 'name': 'untitled', 'mimeType': 'audio/ogg'},
          ],
        },
      ]).list('folder123');

      expect(listing.folders.map((f) => (f.id, f.name)), [('f1', 'Kind of Blue'), ('f2', 'Shortcut to Jazz')]);
      expect(listing.tracks.map((t) => (t.id, t.title, t.trackNumber, t.format)), [
        ('a2', 'So What', 1, 'MP3'),
        ('a1', 'Freddie Freeloader', 2, 'FLAC'),
        ('a3', 'untitled', null, 'OGG'),
      ]);

      expect(requests, hasLength(2));
      final q = requests.first.url.queryParameters;
      expect(q['q'], "'folder123' in parents and trashed = false");
      expect(requests.first.headers['Authorization'], 'Bearer token-1');
      expect(requests.last.url.queryParameters['pageToken'], 'p2');
    });

    test('root folder is "root"', () async {
      await source([
        {'files': <Object>[]},
      ]).list(null);
      expect(requests.single.url.queryParameters['q'], "'root' in parents and trashed = false");
    });

    test('streams carry the access token', () async {
      final stream = await source(const []).resolve(const Track(id: 'a1', sourceId: 'googledrive', title: 'x'));
      expect(stream.uri.toString(), 'https://www.googleapis.com/drive/v3/files/a1?alt=media');
      expect(stream.headers, {'Authorization': 'Bearer token-1'});
    });
  });

  group('tracksUnder', () {
    Track song(String id) => Track(id: id, sourceId: 'fake', title: id);

    test('collects tracks from every sub-folder', () async {
      final drive = _FakeDrive({
        'a': FolderListing(folders: const [Folder(id: 'a1', name: 'CD 1')], tracks: [song('a')]),
        'a1': FolderListing(folders: const [], tracks: [song('a1')]),
        'b': FolderListing(folders: const [], tracks: [song('b')]),
      });
      final root = FolderListing(
        folders: const [Folder(id: 'a', name: 'A'), Folder(id: 'b', name: 'B')],
        tracks: [song('root')],
      );
      final batches = await tracksUnder(drive, root).toList();
      expect(batches.expand((b) => b).map((t) => t.id).toSet(), {'root', 'a', 'a1', 'b'});
    });

    test('skips folders that fail to load', () async {
      final drive = _FakeDrive({'ok': FolderListing(folders: const [], tracks: [song('ok')])});
      final root = const FolderListing(
        folders: [Folder(id: 'missing', name: 'Gone'), Folder(id: 'ok', name: 'Ok')],
        tracks: [],
      );
      final batches = await tracksUnder(drive, root).toList();
      expect(batches.expand((b) => b).map((t) => t.id), ['ok']);
    });

    test('OneDrive lists a whole subtree through delta pages', () async {
      final requests = <Uri>[];
      final pages = [
        {
          'value': [
            {'id': 'f', 'name': 'Album', 'folder': {'childCount': 2}},
            {'id': 't1', 'name': '01 Intro.flac', 'file': {}, 'audio': {'title': 'Intro', 'track': 1}},
            {'id': 'x', 'name': 'cover.jpg', 'file': {}},
          ],
          '@odata.nextLink': 'https://graph.microsoft.com/v1.0/next',
        },
        {
          'value': [
            {'id': 't2', 'name': '02 Outro.mp3', 'file': {}},
            {'id': 'gone', 'name': 'old.mp3', 'file': {}, 'deleted': {'state': 'deleted'}},
          ],
          '@odata.deltaLink': 'https://graph.microsoft.com/v1.0/delta-token',
        },
      ];
      var page = 0;
      final source = OneDriveSource(
        _FakeAuth(),
        client: MockClient((request) async {
          requests.add(request.url);
          return http.Response(jsonEncode(pages[page++]), 200);
        }),
      );
      final batches = await source.tracksUnder('folder1').toList();
      expect(batches.expand((b) => b).map((t) => t.title), ['Intro', 'Outro']);
      expect(requests.first.path, '/v1.0/me/drive/items/folder1/delta');
      expect(requests.last.toString(), 'https://graph.microsoft.com/v1.0/next');
    });
  });

  group('musicRootOf', () {
    const docs = Folder(id: 'd', name: 'Documents');

    test('opens a single Music folder directly', () async {
      final drive = _FakeDrive({
        null: const FolderListing(
          folders: [
            docs,
            Folder(id: 'm', name: 'Música'),
          ],
          tracks: [],
        ),
        'm': const FolderListing(
          folders: [Folder(id: 'a', name: 'Kind of Blue')],
          tracks: [],
        ),
      });
      final listing = await musicRootOf(drive);
      expect(listing.folders.single.name, 'Kind of Blue');
    });

    test("recognises the provider's Music folder whatever its name", () async {
      final drive = _FakeDrive({
        null: const FolderListing(
          folders: [
            docs,
            Folder(id: 'm', name: 'Canciones', isMusicLibrary: true),
          ],
          tracks: [],
        ),
        'm': const FolderListing(folders: [], tracks: []),
      });
      await musicRootOf(drive);
      expect(drive.listed, [null, 'm']);
    });

    test('keeps several matches and root tracks; drops the rest', () async {
      const song = Track(id: 's', sourceId: 'fake', title: 'Song');
      final drive = _FakeDrive({
        null: const FolderListing(
          folders: [
            docs,
            Folder(id: 'm1', name: 'Music'),
            Folder(id: 'm2', name: 'MUSIQUE'),
          ],
          tracks: [song],
        ),
      });
      final listing = await musicRootOf(drive);
      expect(listing.folders.map((f) => f.id), ['m1', 'm2']);
      expect(listing.tracks, [song]);
    });

    test('no Music folder gives an empty listing', () async {
      final drive = _FakeDrive({
        null: const FolderListing(folders: [docs], tracks: []),
      });
      expect((await musicRootOf(drive)).isEmpty, isTrue);
    });
  });
}

class _FakeAuth extends LoopbackOAuth {
  _FakeAuth() : super(googleDriveOAuth);

  @override
  Future<String> accessToken() async => 'token-1';
}

class _FakeDrive implements CloudSource {
  _FakeDrive(this.folders);

  final Map<String?, FolderListing> folders;
  final listed = <String?>[];

  @override
  Future<FolderListing> list(String? folderId) async {
    listed.add(folderId);
    return folders[folderId]!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
