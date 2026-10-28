import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/models.dart';
import '../auth/loopback_oauth.dart';
import '../cloud_source.dart';

/// OAuth clients from Google Cloud Console, supplied at build time: a
/// "Desktop app" client (`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`) and, for
/// the web build, a "Web application" client (`GOOGLE_WEB_CLIENT_ID`, ...).
const _clientIdDefine = kIsWeb ? 'GOOGLE_WEB_CLIENT_ID' : 'GOOGLE_CLIENT_ID';
const googleClientId = kIsWeb
    ? String.fromEnvironment('GOOGLE_WEB_CLIENT_ID')
    : String.fromEnvironment('GOOGLE_CLIENT_ID');

/// Neither secret is confidential: the desktop one ships in the binary
/// (Google documents installed apps as public clients) and the web one in
/// the page's script, but Google's token endpoint requires them.
const googleClientSecret = kIsWeb
    ? String.fromEnvironment('GOOGLE_WEB_CLIENT_SECRET')
    : String.fromEnvironment('GOOGLE_CLIENT_SECRET');

const googleDriveOAuth = OAuthConfig(
  providerName: 'Google Drive',
  clientId: googleClientId,
  clientSecret: googleClientSecret,
  authorizeUrl: 'https://accounts.google.com/o/oauth2/v2/auth',
  tokenUrl: 'https://oauth2.googleapis.com/token',
  scopes: 'https://www.googleapis.com/auth/drive.readonly',
  storageKey: 'googledrive.refresh_token',
  // Google recommends the IP literal for loopback redirects.
  redirectHost: '127.0.0.1',
  // offline + consent guarantees a refresh token on every sign-in.
  extraAuthorizeParams: {'access_type': 'offline', 'prompt': 'consent select_account'},
);

/// Browses and streams music from Google Drive (Drive API v3).
///
/// Drive has no pre-authenticated download links, so streams carry the
/// access token in an Authorization header. A browser's audio player can't
/// send one, so the web build streams through the host's `/drive/` proxy
/// (worker/index.js), which adds it. Tags come from the files themselves
/// since Drive doesn't extract audio metadata.
class GoogleDriveSource implements CloudSource {
  GoogleDriveSource(this.auth, {http.Client? client}) : _http = client ?? http.Client();

  static const _folderMime = 'application/vnd.google-apps.folder';
  static const _shortcutMime = 'application/vnd.google-apps.shortcut';

  @override
  final LoopbackOAuth auth;
  final http.Client _http;

  @override
  String get id => 'googledrive';

  @override
  String get displayName => 'Google Drive';

  @override
  String get signInLabel => 'Sign in with Google';

  @override
  String get clientIdDefine => _clientIdDefine;

  @override
  Future<FolderListing> list(String? folderId) async {
    final folders = <Folder>[];
    final tracks = <Track>[];

    String? pageToken;
    do {
      final page = await _get(Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': "'${folderId ?? 'root'}' in parents and trashed = false",
        'fields': 'nextPageToken, files(id, name, mimeType, shortcutDetails(targetId, targetMimeType))',
        'orderBy': 'folder,name_natural',
        'pageSize': '1000',
        'pageToken': ?pageToken,
      }));
      for (final file in (page['files'] as List).cast<Map<String, dynamic>>()) {
        // Shortcuts behave like the folder or file they point to.
        var mime = file['mimeType'] as String;
        var id = file['id'] as String;
        final shortcut = file['shortcutDetails'] as Map<String, dynamic>?;
        if (mime == _shortcutMime && shortcut != null) {
          mime = shortcut['targetMimeType'] as String? ?? '';
          id = shortcut['targetId'] as String? ?? id;
        }
        final name = file['name'] as String;

        if (mime == _folderMime) {
          folders.add(Folder(id: id, name: name));
          continue;
        }
        final ext = extensionOf(name);
        if (!audioExtensions.contains(ext) && !mime.startsWith('audio/')) continue;
        final fromName = titleFromFileName(name);
        tracks.add(Track(
          id: id,
          sourceId: this.id,
          title: fromName.title,
          trackNumber: fromName.number,
          format: (ext ?? mime.split('/').last).toUpperCase(),
        ));
      }
      pageToken = page['nextPageToken'] as String?;
    } while (pageToken != null);

    tracks.sort(compareTracks);
    return FolderListing(folders: folders, tracks: tracks);
  }

  @override
  Future<PlayableStream> resolve(Track track) async {
    if (kIsWeb) {
      // Browsers keep making range requests while playing (Safari in small
      // chunks), so the token must outlive the track, not just the start.
      final token = await auth.accessToken(minValidity: const Duration(minutes: 30));
      return PlayableStream(Uri.base.resolve('drive/${track.id}').replace(queryParameters: {
        'token': token,
        // Lets the proxy name the audio type when Drive only knows it as bytes.
        'format': ?track.format?.toLowerCase(),
      }));
    }
    // Fetch a fresh token per track: a token expiring mid-stream would only
    // break seeking (new range requests), not the current playback.
    final token = await auth.accessToken();
    return PlayableStream(
      Uri.https('www.googleapis.com', '/drive/v3/files/${track.id}', {'alt': 'media'}),
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final token = await auth.accessToken();
    final response = await _http.get(uri, headers: {'Authorization': 'Bearer $token'});
    if (response.statusCode != 200) {
      throw http.ClientException('Drive ${response.statusCode}: ${response.body}', uri);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
