/// A playable audio item, independent of where it is stored.
class Track {
  const Track({
    required this.id,
    required this.sourceId,
    required this.title,
    this.artist,
    this.album,
    this.duration,
    this.format,
    this.trackNumber,
    this.albumArtist,
    this.year,
    this.streamHint,
    this.artworkUrl,
    this.isLive = false,
  });

  /// Provider-specific identifier (e.g. a OneDrive item id or a URL).
  final String id;

  /// The [MusicSource.id] this track belongs to.
  final String sourceId;

  final String title;
  final String? artist;
  final String? album;
  final Duration? duration;

  /// Upper-case file extension, e.g. `FLAC`, `MP3`.
  final String? format;
  final int? trackNumber;
  final String? albumArtist;
  final int? year;

  /// A short-lived direct URL the source already handed out (e.g. OneDrive's
  /// download URL from a folder listing). Lets metadata reads skip a
  /// [MusicSource.resolve] round-trip. Not part of equality.
  final String? streamHint;

  /// Artwork the source supplies directly (e.g. a radio station's logo).
  final String? artworkUrl;

  /// An endless stream (radio): no duration, no tags to read, no seeking.
  final bool isLive;

  String get subtitle =>
      [artist, album].whereType<String>().where((s) => s.isNotEmpty).join(' — ');

  /// Seed for generated artwork; tracks of the same album share colours,
  /// stations each get their own.
  String get artSeed => isLive ? title : album ?? artist ?? title;

  /// Whether the source already supplied enough to display the track.
  bool get hasBasicTags => artist != null && album != null && duration != null;

  Track copyWith({
    String? title,
    String? artist,
    String? album,
    Duration? duration,
    int? trackNumber,
    String? albumArtist,
    int? year,
  }) =>
      Track(
        id: id,
        sourceId: sourceId,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        album: album ?? this.album,
        duration: duration ?? this.duration,
        format: format,
        trackNumber: trackNumber ?? this.trackNumber,
        albumArtist: albumArtist ?? this.albumArtist,
        year: year ?? this.year,
        streamHint: streamHint,
        artworkUrl: artworkUrl,
        isLive: isLive,
      );

  @override
  bool operator ==(Object other) =>
      other is Track && other.id == id && other.sourceId == sourceId;

  @override
  int get hashCode => Object.hash(id, sourceId);
}

/// A folder inside a source.
class Folder {
  const Folder({required this.id, required this.name, this.childCount});

  final String id;
  final String name;
  final int? childCount;
}

/// The contents of one folder: sub-folders first, then tracks.
class FolderListing {
  const FolderListing({required this.folders, required this.tracks});

  final List<Folder> folders;
  final List<Track> tracks;

  bool get isEmpty => folders.isEmpty && tracks.isEmpty;
}

/// Everything the player needs to start streaming a track.
class PlayableStream {
  const PlayableStream(this.uri, {this.headers = const {}});

  final Uri uri;
  final Map<String, String> headers;
}

/// Album order: track number first, then title.
int compareTracks(Track a, Track b) {
  final byNumber = (a.trackNumber ?? 1 << 20).compareTo(b.trackNumber ?? 1 << 20);
  return byNumber != 0 ? byNumber : a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

const audioExtensions = {
  'mp3', 'flac', 'm4a', 'aac', 'alac', 'ogg', 'oga', 'opus', 'wav', 'aiff', 'aif', 'wma',
};

String? extensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return null;
  return fileName.substring(dot + 1).toLowerCase();
}

String stripExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot > 0 ? fileName.substring(0, dot) : fileName;
}

final _numberedName = RegExp(r'^(\d{1,3})\s*(?:[-–._)]\s*|\s+)(.+)$');

/// Best guess at track number and title from a file name such as
/// "03 - So What.flac" or "3. So What.mp3". Used until real tags are read.
({int? number, String title}) titleFromFileName(String fileName) {
  final base = stripExtension(fileName).trim();
  final match = _numberedName.firstMatch(base);
  if (match == null) return (number: null, title: base);
  return (number: int.parse(match.group(1)!), title: match.group(2)!.trim());
}
