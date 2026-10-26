import 'dart:convert';

import 'package:amuse/core/models.dart';
import 'package:amuse/sources/auth/loopback_oauth.dart';
import 'package:amuse/sources/google_drive/google_drive_source.dart';
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
      final stream = await source(const []).resolve(
          const Track(id: 'a1', sourceId: 'googledrive', title: 'x'));
      expect(stream.uri.toString(), 'https://www.googleapis.com/drive/v3/files/a1?alt=media');
      expect(stream.headers, {'Authorization': 'Bearer token-1'});
    });
  });
}

class _FakeAuth extends LoopbackOAuth {
  _FakeAuth() : super(googleDriveOAuth);

  @override
  Future<String> accessToken() async => 'token-1';
}
