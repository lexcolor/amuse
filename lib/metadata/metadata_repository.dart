import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../core/models.dart';
import '../platform/document_tree.dart';
import '../sources/music_source.dart';
import 'header_reader.dart';
import 'lyrics.dart';
import 'online_lookup.dart';
import 'tag_parser.dart';

/// Resolves embedded tags, cover art and lyrics for tracks, caching
/// everything on disk so each file/album is looked up only once.
///
/// Cover lookup order: picture embedded in the file → image in the same
/// folder → Deezer → iTunes.
/// Lyrics lookup order: lyrics embedded in the file → LRCLIB.
class MetadataRepository {
  MetadataRepository({
    required this.cacheDir,
    required this.sources,
    required http.Client client,
    this.documents = const DocumentTree(),
  })  : _http = client,
        _online = OnlineLookup(client);

  final Directory cacheDir;
  final Map<String, MusicSource> sources;

  /// Reads Android `content:` files (tags and folder covers).
  final DocumentTree documents;
  final http.Client _http;
  final OnlineLookup _online;

  /// At most a few header downloads at once, so opening a big folder
  /// doesn't saturate the connection.
  final _headerPool = Pool(4);

  /// Missing covers/lyrics are re-tried after this long.
  static const _missTtl = Duration(days: 14);

  final _inflight = <String, Future<Object?>>{};

  // ------------------------------------------------------------- tags ---

  /// Tags embedded in [track]'s file (picture excluded; see [coverFor]).
  Future<EmbeddedTags> tagsFor(Track track) => _once('tags:${_trackKey(track)}', () async {
        final file = _file('tags', '${_trackKey(track)}.json');
        if (await file.exists()) {
          return EmbeddedTags.fromJson(jsonDecode(await file.readAsString()) as Map<String, Object?>);
        }

        final tags = await _headerPool.run(() => _readTags(track));
        await _write(file, utf8.encode(jsonEncode(tags.toJson())));

        // Keep the embedded picture as the album's cover.
        final picture = tags.picture;
        if (picture != null) {
          final cover = _coverFile(_albumKey(track.enrichedWith(tags)), picture.extension);
          if (!await cover.exists()) await _write(cover, picture.bytes);
        }
        return tags;
      });

  Future<EmbeddedTags> _readTags(Track track) async {
    final hint = track.streamHint;
    if (hint != null) {
      try {
        return await readRemoteTags(_http, PlayableStream(Uri.parse(hint)));
      } on http.ClientException {
        // Hint expired; fall through to a fresh URL.
      }
    }
    final stream = await sources[track.sourceId]!.resolve(track);
    if (stream.uri.scheme == 'file') return readLocalTags(File.fromUri(stream.uri));
    if (stream.uri.scheme == 'content') {
      final uri = stream.uri.toString();
      return readTagsWith((offset, length) => documents.read(uri, offset, length));
    }
    return readRemoteTags(_http, stream);
  }

  // ----------------------------------------------------------- covers ---

  /// The cover image for [track]'s album, or null when none can be found.
  Future<File?> coverFor(Track track) {
    final key = _albumKey(track);
    return _once('cover:$key', () async {
      final cached = await _findCover(key);
      if (cached != null) return cached;
      final miss = _file('covers', '$key.miss');
      if (await _isFresh(miss)) return null;

      // 1. Embedded picture (tagsFor stores it while reading the header).
      try {
        final tags = await tagsFor(track);
        // tagsFor files the picture under the key derived from the file's own
        // tags, which can differ slightly from what the source reported.
        final embedded = await _findCover(_albumKey(track.enrichedWith(tags)));
        if (embedded != null) {
          if (_albumKey(track.enrichedWith(tags)) == key) return embedded;
          final ext = embedded.path.substring(embedded.path.lastIndexOf('.') + 1);
          return await embedded.copy(_coverFile(key, ext).path);
        }
      } catch (_) {
        // Unreadable file; try online.
      }

      // 2. An image the source found next to the file (cover.jpg and the like).
      final artwork = track.artworkUrl;
      if (artwork != null) {
        final uri = Uri.parse(artwork);
        final file = switch (uri.scheme) {
          'file' => File.fromUri(uri),
          'content' => await _copyDocument(artwork, _coverFile(key, _imageExtension(artwork))),
          _ => await artworkFor(artwork),
        };
        if (file != null && await file.exists()) return file;
      }

      // 3. Online lookup by album + artist.
      final artist = track.albumArtist ?? track.artist;
      final album = track.album;
      if (artist != null && album != null) {
        try {
          final url = await _online.findCoverUrl(artist: artist, album: album);
          final bytes = url == null ? null : await _online.download(url);
          if (bytes != null) {
            final file = _coverFile(key, url!.toLowerCase().contains('.png') ? 'png' : 'jpg');
            await _write(file, bytes);
            return file;
          }
        } on Exception {
          return null; // Network trouble: don't record a miss.
        }
      }
      await _write(miss, const []);
      return null;
    });
  }

  Future<File?> _findCover(String key) async {
    for (final ext in const ['jpg', 'png', 'webp']) {
      final file = _coverFile(key, ext);
      if (await file.exists()) return file;
    }
    return null;
  }

  /// Artwork a source links to directly (radio station logos), cached by URL.
  Future<File?> artworkFor(String url) {
    final key = _hash('artwork|$url');
    return _once('artwork:$key', () async {
      final file = _file('artwork', key);
      if (await file.exists()) return file;
      final miss = _file('artwork', '$key.miss');
      if (await _isFresh(miss)) return null;
      final Uint8List? bytes;
      try {
        bytes = await _online.download(url);
      } on Exception {
        return null; // Network trouble: don't record a miss.
      }
      await _write(bytes == null ? miss : file, bytes ?? const []);
      return bytes == null ? null : file;
    });
  }

  File _coverFile(String key, String ext) => _file('covers', '$key.$ext');

  /// Copies an Android document (a folder's cover.jpg) into the cache, since
  /// image widgets can't open `content:` URIs.
  Future<File?> _copyDocument(String uri, File target) async {
    const chunk = 256 * 1024;
    final bytes = BytesBuilder(copy: false);
    try {
      while (true) {
        final part = await documents.read(uri, bytes.length, chunk);
        bytes.add(part);
        if (part.length < chunk || bytes.length > 32 * 1024 * 1024) break;
      }
    } on DocumentAccessException {
      return null;
    }
    if (bytes.isEmpty) return null;
    await _write(target, bytes.takeBytes());
    return target;
  }

  static String _imageExtension(String uri) {
    final name = uri.toLowerCase();
    return name.endsWith('.png') ? 'png' : name.endsWith('.webp') ? 'webp' : 'jpg';
  }

  // ----------------------------------------------------------- lyrics ---

  /// Lyrics embedded in [track]'s file; failing that, and only when
  /// [allowOnline] is set (an opt-in user setting), lyrics from LRCLIB.
  /// The disk cache holds online results only; embedded lyrics come from the
  /// cached tags.
  Future<Lyrics?> lyricsFor(Track track, {Duration? duration, bool allowOnline = false}) {
    final key = _trackKey(track);
    return _once('lyrics:$key:$allowOnline', () async {
      try {
        final embedded = (await tagsFor(track)).lyrics;
        if (embedded != null) {
          final synced = parseLrc(embedded);
          return synced.isNotEmpty
              ? Lyrics(synced: synced, source: LyricsSource.embedded)
              : Lyrics(plain: embedded, source: LyricsSource.embedded);
        }
      } catch (_) {
        // Unreadable file; fall through.
      }
      if (!allowOnline) return null;

      final file = _file('lyrics', '$key.json');
      if (await file.exists()) {
        if (await file.length() == 0) {
          if (await _isFresh(file)) return null;
        } else {
          return Lyrics.fromJson(jsonDecode(await file.readAsString()) as Map<String, Object?>);
        }
      }

      final artist = track.artist ?? track.albumArtist;
      if (artist == null) return null;
      final Lyrics? lyrics;
      try {
        lyrics = await _online.findLyrics(
          title: track.title,
          artist: artist,
          album: track.album,
          duration: duration ?? track.duration,
        );
      } on Exception {
        return null; // Network trouble: don't record a miss.
      }
      await _write(file, lyrics == null ? const [] : utf8.encode(jsonEncode(lyrics.toJson())));
      return lyrics;
    });
  }

  // ---------------------------------------------------------- helpers ---

  /// Runs [job] once per [key] at a time; concurrent callers share the result.
  Future<T> _once<T>(String key, Future<T> Function() job) {
    final existing = _inflight[key];
    if (existing != null) return existing.then((v) => v as T);
    // Block body: returning the removed future here would make whenComplete
    // wait on itself and never finish.
    final future = job().whenComplete(() {
      _inflight.remove(key);
    });
    _inflight[key] = future;
    return future;
  }

  File _file(String folder, String name) =>
      File('${cacheDir.path}${Platform.pathSeparator}$folder${Platform.pathSeparator}$name');

  Future<void> _write(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<bool> _isFresh(File file) async =>
      await file.exists() && DateTime.now().difference(await file.lastModified()) < _missTtl;

  static String _hash(String s) => sha1.convert(utf8.encode(s)).toString();

  static String _trackKey(Track t) => _hash('${t.sourceId}|${t.id}');

  /// Tracks of the same album share one cover; tracks without an album get their own.
  static String _albumKey(Track t) {
    final album = t.album;
    if (album == null) return _trackKey(t);
    return _hash('album|${normalizeName(t.albumArtist ?? t.artist ?? '')}|${normalizeName(album)}');
  }
}

extension TrackEnrichment on Track {
  /// Fills gaps with values read from the file's own tags (which win where
  /// the source only had a file name).
  Track enrichedWith(EmbeddedTags tags) => copyWith(
        title: tags.title,
        artist: tags.artist ?? tags.albumArtist,
        album: tags.album,
        duration: duration ?? tags.duration,
        trackNumber: tags.trackNumber,
        albumArtist: tags.albumArtist,
        year: tags.year,
      );
}
