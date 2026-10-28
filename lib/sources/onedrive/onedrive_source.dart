import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/models.dart';
import '../auth/loopback_oauth.dart';
import '../cloud_source.dart';
import '../music_source.dart';

/// Browses and streams music from the signed-in user's OneDrive through
/// Microsoft Graph.
class OneDriveSource implements CloudSource, DeepListing {
  OneDriveSource(this.auth, {http.Client? client}) : _http = client ?? http.Client();

  static const _graph = 'https://graph.microsoft.com/v1.0';

  @override
  final LoopbackOAuth auth;
  final http.Client _http;

  @override
  String get id => 'onedrive';

  @override
  String get displayName => 'OneDrive';

  @override
  String get signInLabel => 'Sign in with Microsoft';

  @override
  String get clientIdDefine => 'ONEDRIVE_CLIENT_ID';

  @override
  Future<FolderListing> list(String? folderId) async {
    final base = folderId == null ? '/me/drive/root' : '/me/drive/items/$folderId';
    final folders = <Folder>[];
    final tracks = <Track>[];

    Uri? next = Uri.parse('$_graph$base/children?\$top=999');
    while (next != null) {
      final page = await _get(next);
      for (final item in (page['value'] as List).cast<Map<String, dynamic>>()) {
        if (item['folder'] != null) {
          folders.add(Folder(
            id: item['id'] as String,
            name: item['name'] as String,
            childCount: (item['folder'] as Map)['childCount'] as int?,
            isMusicLibrary: (item['specialFolder'] as Map?)?['name'] == 'music',
          ));
        } else if (item['file'] != null) {
          final track = _trackFrom(item);
          if (track != null) tracks.add(track);
        }
      }
      final link = page['@odata.nextLink'] as String?;
      next = link == null ? null : Uri.parse(link);
    }

    folders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    tracks.sort(compareTracks);
    return FolderListing(folders: folders, tracks: tracks);
  }

  /// OneDrive Personal's delta query returns a folder's whole subtree in a
  /// few large pages instead of one request per sub-folder.
  @override
  Stream<List<Track>> tracksUnder(String folderId) async* {
    Uri? next = Uri.parse('$_graph/me/drive/items/$folderId/delta?\$select=id,name,file,audio,deleted');
    while (next != null) {
      final page = await _get(next);
      final tracks = [
        for (final item in (page['value'] as List).cast<Map<String, dynamic>>())
          if (item['file'] != null && item['deleted'] == null) ?_trackFrom(item),
      ];
      if (tracks.isNotEmpty) yield tracks;
      final link = page['@odata.nextLink'] as String?;
      next = link == null ? null : Uri.parse(link);
    }
  }

  @override
  Future<PlayableStream> resolve(Track track) async {
    // Download URLs expire after about an hour, so always fetch a fresh one.
    // No $select: OneDrive Personal drops the downloadUrl annotation when
    // it is named there.
    final item = await _get(Uri.parse('$_graph/me/drive/items/${track.id}'));
    final url = item['@microsoft.graph.downloadUrl'] as String? ?? await _contentRedirect(track.id);
    if (url == null) throw StateError('OneDrive returned no download URL for ${track.title}');
    return PlayableStream(Uri.parse(url));
  }

  /// `/content` answers with a 302 to the same pre-authenticated URL.
  /// Browsers follow redirects themselves, so this only helps on native.
  Future<String?> _contentRedirect(String itemId) async {
    final token = await auth.accessToken();
    final request = http.Request('GET', Uri.parse('$_graph/me/drive/items/$itemId/content'))
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer $token';
    final response = await _http.send(request);
    await response.stream.drain<void>();
    return response.isRedirect || response.statusCode == 302 ? response.headers['location'] : null;
  }

  Track? _trackFrom(Map<String, dynamic> item) {
    final name = item['name'] as String;
    final ext = extensionOf(name);
    if (ext == null || !audioExtensions.contains(ext)) return null;

    // OneDrive Personal extracts common tags into the `audio` facet.
    final audio = item['audio'] as Map<String, dynamic>?;
    final durationMs = audio?['duration'] as num?;
    final fromName = titleFromFileName(name);
    return Track(
      id: item['id'] as String,
      sourceId: id,
      title: _nonEmpty(audio?['title']) ?? fromName.title,
      artist: _nonEmpty(audio?['artist']) ?? _nonEmpty(audio?['albumArtist']),
      album: _nonEmpty(audio?['album']),
      duration: durationMs == null ? null : Duration(milliseconds: durationMs.toInt()),
      format: ext.toUpperCase(),
      trackNumber: audio?['track'] as int? ?? fromName.number,
      albumArtist: _nonEmpty(audio?['albumArtist']),
      year: audio?['year'] as int?,
      streamHint: item['@microsoft.graph.downloadUrl'] as String?,
    );
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final token = await auth.accessToken();
    final response = await _http.get(uri, headers: {'Authorization': 'Bearer $token'});
    if (response.statusCode != 200) {
      throw http.ClientException('Graph ${response.statusCode}: ${response.body}', uri);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static String? _nonEmpty(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}
