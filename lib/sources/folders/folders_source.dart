import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/models.dart';
import '../../platform/document_tree.dart';
import '../music_source.dart';
import 'locations.dart';

/// Image files used as the cover of the folder they sit in.
final _coverName = RegExp(r'^(cover|folder|front|album|albumart)\.(jpe?g|png|webp)$', caseSensitive: false);

/// Music the user pointed Amuse at: folders on this device (or a network
/// share), web folders (a server's file index page), and direct links.
///
/// Folder ids are absolute paths or absolute URLs, so any depth can be
/// listed without remembering how the user got there.
class FoldersSource implements MusicSource {
  FoldersSource(this._locations, {http.Client? client, this.documents = const DocumentTree()})
      : _http = client ?? http.Client();

  /// Read on every root listing, so adding a location doesn't rebuild sources.
  final List<SavedLocation> Function() _locations;
  final http.Client _http;

  /// Android folders, whose ids are `content://` URIs.
  final DocumentTree documents;

  @override
  String get id => 'folders';

  @override
  String get displayName => 'Folders';

  @override
  Future<FolderListing> list(String? folderId) async {
    if (folderId == null) {
      final locations = _locations();
      return FolderListing(
        folders: [
          for (final l in locations)
            if (l.kind != LocationKind.link) Folder(id: l.uri, name: l.name),
        ],
        tracks: [
          for (final l in locations)
            if (l.kind == LocationKind.link) _track(l.uri, l.name, isLive: l.isLive),
        ],
      );
    }
    if (isWebAddress(folderId)) return _listWeb(folderId);
    return isContentUri(folderId) ? _listDocuments(folderId) : _listLocal(folderId);
  }

  @override
  Future<PlayableStream> resolve(Track track) async => PlayableStream(trackUri(track.id));

  /// Track ids are web addresses, `file:` URIs (single local files added as
  /// links), Android `content:` URIs or plain paths (files found while
  /// listing a folder).
  static Uri trackUri(String id) =>
      isWebAddress(id) || id.startsWith('file:') || isContentUri(id) ? Uri.parse(id) : Uri.file(id);

  Future<FolderListing> _listDocuments(String uri) async {
    final folders = <Folder>[];
    final tracks = <Track>[];
    String? cover;
    for (final entry in await documents.list(uri)) {
      if (entry.name.startsWith('.')) continue;
      if (entry.isFolder) {
        folders.add(Folder(id: entry.uri, name: entry.name));
      } else if (_coverName.hasMatch(entry.name)) {
        cover ??= entry.uri;
      } else if (audioExtensions.contains(extensionOf(entry.name))) {
        tracks.add(_track(entry.uri, entry.name));
      }
    }
    return _finish(folders, tracks, cover);
  }

  Future<FolderListing> _listLocal(String path) async {
    final folders = <Folder>[];
    final tracks = <Track>[];
    String? cover;
    try {
      await for (final entity in Directory(path).list(followLinks: false)) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('.') || name.startsWith(r'$')) continue;
        if (entity is Directory) {
          folders.add(Folder(id: entity.path, name: name));
        } else if (entity is File) {
          if (_coverName.hasMatch(name)) {
            cover ??= entity.uri.toString();
          } else if (audioExtensions.contains(extensionOf(name))) {
            tracks.add(_track(entity.path, name));
          }
        }
      }
    } on FileSystemException catch (e) {
      throw FileSystemException(
        e.osError?.errorCode == 5 ? 'Amuse isn\'t allowed to read this folder' : 'Couldn\'t open this folder',
        path,
      );
    }
    return _finish(folders, tracks, cover);
  }

  Future<FolderListing> _listWeb(String url) async {
    final base = Uri.parse(url.endsWith('/') ? url : '$url/');
    final response = await _http.get(base);
    if (response.statusCode != 200) {
      throw http.ClientException('The server answered ${response.statusCode}', base);
    }
    final index = parseWebIndex(response.body, base);
    String? cover;
    for (final f in index.files) {
      if (_coverName.hasMatch(f.name)) cover ??= f.url.toString();
    }
    return _finish(
      [for (final d in index.folders) Folder(id: d.url.toString(), name: d.name)],
      [
        for (final f in index.files)
          if (audioExtensions.contains(extensionOf(f.name))) _track(f.url.toString(), f.name),
      ],
      cover,
    );
  }

  FolderListing _finish(List<Folder> folders, List<Track> files, String? cover) {
    folders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final withCover = [
      for (final t in preferredFormats(files))
        cover == null
            ? t
            : Track(
                id: t.id,
                sourceId: t.sourceId,
                title: t.title,
                trackNumber: t.trackNumber,
                format: t.format,
                artworkUrl: cover,
              ),
    ]..sort(compareTracks);
    return FolderListing(folders: folders, tracks: withCover);
  }

  Track _track(String id, String fileName, {bool isLive = false}) {
    final fromName = titleFromFileName(fileName);
    return Track(
      id: id,
      sourceId: this.id,
      title: isLive ? fileName : fromName.title,
      trackNumber: isLive ? null : fromName.number,
      format: extensionOf(fileName)?.toUpperCase(),
      isLive: isLive,
    );
  }
}

/// Best first: lossless, then the common lossy formats.
const _formatRank = ['FLAC', 'ALAC', 'WAV', 'AIFF', 'AIF', 'M4A', 'OPUS', 'OGG', 'OGA', 'AAC', 'MP3', 'WMA'];

/// One track per song when a folder holds the same file in several formats
/// (archive.org lists FLAC, MP3 and OGG copies side by side), keeping the
/// best-quality copy.
List<Track> preferredFormats(List<Track> files) {
  int rank(Track t) {
    final i = _formatRank.indexOf(t.format ?? '');
    return i < 0 ? _formatRank.length : i;
  }

  String stem(Track t) {
    final name = t.id.split(RegExp(r'[\\/]')).last;
    try {
      return stripExtension(Uri.decodeComponent(name)).toLowerCase();
    } on ArgumentError {
      return stripExtension(name).toLowerCase();
    }
  }

  final best = <String, Track>{};
  for (final t in files) {
    final key = stem(t);
    final current = best[key];
    if (current == null || rank(t) < rank(current)) best[key] = t;
  }
  return best.values.toList();
}

bool isWebAddress(String s) => s.startsWith('http://') || s.startsWith('https://');

class WebEntry {
  const WebEntry(this.name, this.url);

  final String name;
  final Uri url;
}

/// Folders and files linked from a server's index page (Apache, nginx and
/// similar "Index of /…" pages, or archive.org download pages). Only links
/// directly inside [base] count; parent, sort and external links are ignored.
({List<WebEntry> folders, List<WebEntry> files}) parseWebIndex(String html, Uri base) {
  final folders = <WebEntry>[], files = <WebEntry>[];
  final seen = <String>{};
  for (final m in RegExp(r'''href\s*=\s*["']([^"'#]+)["']''', caseSensitive: false).allMatches(html)) {
    final Uri url;
    try {
      url = base.resolve(_unescapeHtml(m.group(1)!));
    } on FormatException {
      continue;
    }
    if (url.origin != base.origin || url.hasQuery || !url.path.startsWith(base.path)) continue;
    final rest = url.path.substring(base.path.length);
    final isFolder = rest.endsWith('/');
    final segment = isFolder ? rest.substring(0, rest.length - 1) : rest;
    // Direct children only.
    if (segment.isEmpty || segment.contains('/') || !seen.add(url.path)) continue;
    final String name;
    try {
      name = Uri.decodeComponent(segment);
    } on ArgumentError {
      continue;
    }
    (isFolder ? folders : files).add(WebEntry(name, url));
  }
  return (folders: folders, files: files);
}

String _unescapeHtml(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&#39;', "'")
    .replaceAll('&quot;', '"');
