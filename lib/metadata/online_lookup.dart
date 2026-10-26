import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'lyrics.dart';

const _userAgent = 'Amuse/0.1 (personal music player)';

/// Looks up album covers and lyrics from free public services.
class OnlineLookup {
  OnlineLookup(this._http);

  final http.Client _http;

  /// Finds a cover image URL for an album: Deezer first, then iTunes.
  Future<String?> findCoverUrl({required String artist, required String album}) async {
    return await _guard(() => _deezerCover(artist, album)) ??
        await _guard(() => _itunesCover(artist, album));
  }

  Future<Uint8List?> download(String url) async {
    final response = await _http.get(Uri.parse(url), headers: {'User-Agent': _userAgent});
    return response.statusCode == 200 && response.bodyBytes.isNotEmpty ? response.bodyBytes : null;
  }

  Future<String?> _deezerCover(String artist, String album) async {
    final uri = Uri.https('api.deezer.com', '/search/album', {
      'q': 'artist:"${_quoteSafe(artist)}" album:"${_quoteSafe(album)}"',
      'limit': '5',
    });
    final json = await _getJson(uri);
    for (final hit in (json?['data'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      final hitArtist = (hit['artist'] as Map?)?['name'] as String? ?? '';
      if (_similar(hit['title'] as String? ?? '', album) && _similar(hitArtist, artist)) {
        return hit['cover_xl'] as String? ?? hit['cover_big'] as String?;
      }
    }
    return null;
  }

  Future<String?> _itunesCover(String artist, String album) async {
    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': '$artist $album',
      'entity': 'album',
      'limit': '5',
    });
    final json = await _getJson(uri);
    for (final hit in (json?['results'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      if (_similar(hit['collectionName'] as String? ?? '', album) &&
          _similar(hit['artistName'] as String? ?? '', artist)) {
        final art = hit['artworkUrl100'] as String?;
        return art?.replaceFirst(RegExp(r'\d+x\d+bb'), '1000x1000bb');
      }
    }
    return null;
  }

  /// Fetches lyrics from LRCLIB. Returns null when none are known.
  Future<Lyrics?> findLyrics({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) async {
    if (duration != null) {
      final exact = await _getJson(Uri.https('lrclib.net', '/api/get', {
        'track_name': title,
        'artist_name': artist,
        'album_name': ?album,
        'duration': '${duration.inSeconds}',
      }));
      if (exact != null) return _lyricsFrom(exact);
    }

    // No exact match: search and take the closest duration among title/artist matches.
    final results = await _getJsonList(
        Uri.https('lrclib.net', '/api/search', {'track_name': title, 'artist_name': artist}));
    final candidates = results
        .where((r) =>
            _similar(r['trackName'] as String? ?? '', title) &&
            _similar(r['artistName'] as String? ?? '', artist))
        .toList();
    if (candidates.isEmpty) return null;
    if (duration != null) {
      int distance(Map<String, dynamic> r) =>
          (((r['duration'] as num?)?.toDouble() ?? 0) - duration.inSeconds).abs().round();
      candidates.sort((a, b) => distance(a).compareTo(distance(b)));
      if (distance(candidates.first) > 5) return null;
    }
    return _lyricsFrom(candidates.first);
  }

  Lyrics _lyricsFrom(Map<String, dynamic> json) => Lyrics(
        synced: parseLrc(json['syncedLyrics'] as String? ?? ''),
        plain: json['plainLyrics'] as String?,
        instrumental: json['instrumental'] as bool? ?? false,
      );

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    final response = await _http.get(uri, headers: {'User-Agent': _userAgent});
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) throw http.ClientException('HTTP ${response.statusCode}', uri);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  Future<List<Map<String, dynamic>>> _getJsonList(Uri uri) async {
    final response = await _http.get(uri, headers: {'User-Agent': _userAgent});
    if (response.statusCode != 200) return const [];
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return decoded is List ? decoded.cast<Map<String, dynamic>>() : const [];
  }

  static Future<T?> _guard<T>(Future<T?> Function() call) async {
    try {
      return await call();
    } catch (_) {
      return null;
    }
  }

  static String _quoteSafe(String s) => s.replaceAll('"', ' ');
}

/// Loose comparison that ignores case, punctuation, "the", and suffixes like
/// "(Remastered 2011)" or "[Deluxe Edition]".
bool _similar(String a, String b) {
  final x = normalizeName(a), y = normalizeName(b);
  if (x.isEmpty || y.isEmpty) return false;
  return x == y || x.startsWith(y) || y.startsWith(x);
}

String normalizeName(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[\(\[].*?[\)\]]'), ' ')
    .replaceAll(RegExp(r'\b(the|a|an)\b'), ' ')
    .replaceAll('&', 'and')
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');
