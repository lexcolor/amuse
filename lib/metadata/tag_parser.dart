import 'dart:convert';
import 'dart:typed_data';

/// Metadata embedded in an audio file's header.
class EmbeddedTags {
  const EmbeddedTags({
    this.title,
    this.artist,
    this.albumArtist,
    this.album,
    this.trackNumber,
    this.year,
    this.duration,
    this.lyrics,
    this.picture,
  });

  final String? title;
  final String? artist;
  final String? albumArtist;
  final String? album;
  final int? trackNumber;
  final int? year;
  final Duration? duration;
  final String? lyrics;
  final EmbeddedPicture? picture;

  static const empty = EmbeddedTags();

  /// Fields from [this] win; gaps are filled from [other].
  EmbeddedTags mergedWith(EmbeddedTags other) => EmbeddedTags(
        title: title ?? other.title,
        artist: artist ?? other.artist,
        albumArtist: albumArtist ?? other.albumArtist,
        album: album ?? other.album,
        trackNumber: trackNumber ?? other.trackNumber,
        year: year ?? other.year,
        duration: duration ?? other.duration,
        lyrics: lyrics ?? other.lyrics,
        picture: picture ?? other.picture,
      );

  /// JSON form for the disk cache; the picture is stored separately.
  Map<String, Object?> toJson() => {
        'title': title,
        'artist': artist,
        'albumArtist': albumArtist,
        'album': album,
        'trackNumber': trackNumber,
        'year': year,
        'durationMs': duration?.inMilliseconds,
        'lyrics': lyrics,
      };

  factory EmbeddedTags.fromJson(Map<String, Object?> json) => EmbeddedTags(
        title: json['title'] as String?,
        artist: json['artist'] as String?,
        albumArtist: json['albumArtist'] as String?,
        album: json['album'] as String?,
        trackNumber: json['trackNumber'] as int?,
        year: json['year'] as int?,
        duration: json['durationMs'] == null ? null : Duration(milliseconds: json['durationMs'] as int),
        lyrics: json['lyrics'] as String?,
      );
}

class EmbeddedPicture {
  const EmbeddedPicture(this.mimeType, this.bytes);

  final String mimeType;
  final Uint8List bytes;

  String get extension => switch (mimeType.toLowerCase()) {
        'image/png' || 'png' => 'png',
        'image/webp' => 'webp',
        _ => 'jpg',
      };
}

/// Thrown while parsing when the buffer is too short; [bytes] is the total
/// length the parser needs to make progress.
class NeedMoreData implements Exception {
  const NeedMoreData(this.bytes);
  final int bytes;
}

/// Parses ID3v2 (2.2–2.4) and FLAC metadata from the start of a file.
///
/// Throws [NeedMoreData] when [data] doesn't reach far enough. With
/// [truncated] set (the stream ended or hit its size cap) it instead returns
/// whatever it managed to read.
EmbeddedTags parseTags(Uint8List data, {bool truncated = false}) {
  var offset = 0;
  var tags = EmbeddedTags.empty;

  // ID3 tags may precede any format, including FLAC.
  while (_hasMagic(data, offset, 'ID3', truncated)) {
    final (id3, end) = _parseId3(data, offset, truncated);
    tags = tags.mergedWith(id3);
    offset = end;
  }
  if (_hasMagic(data, offset, 'fLaC', truncated)) {
    // Native FLAC tags are preferred over a prepended ID3 tag.
    tags = _parseFlac(data, offset + 4, truncated).mergedWith(tags);
  }
  return tags;
}

bool _hasMagic(Uint8List data, int offset, String magic, bool truncated) {
  if (data.length < offset + magic.length) {
    if (truncated) return false;
    throw NeedMoreData(offset + magic.length);
  }
  for (var i = 0; i < magic.length; i++) {
    if (data[offset + i] != magic.codeUnitAt(i)) return false;
  }
  return true;
}

// ---------------------------------------------------------------- FLAC ----

EmbeddedTags _parseFlac(Uint8List data, int offset, bool truncated) {
  String? title, artist, albumArtist, album, lyrics;
  int? trackNumber, year;
  Duration? duration;
  EmbeddedPicture? picture;

  var pos = offset;
  while (true) {
    if (data.length < pos + 4) {
      if (truncated) break;
      throw NeedMoreData(pos + 4);
    }
    final header = data[pos];
    final type = header & 0x7f;
    final length = (data[pos + 1] << 16) | (data[pos + 2] << 8) | data[pos + 3];
    final body = pos + 4;
    final end = body + length;
    final wanted = type == 0 || type == 4 || (type == 6 && picture == null);

    if (wanted) {
      if (data.length < end) {
        if (truncated) break;
        throw NeedMoreData(end);
      }
      final block = Uint8List.sublistView(data, body, end);
      switch (type) {
        case 0:
          duration = _streamInfoDuration(block);
        case 4:
          final c = _vorbisComments(block);
          title = c['TITLE'];
          artist = c['ARTIST'];
          albumArtist = c['ALBUMARTIST'] ?? c['ALBUM ARTIST'];
          album = c['ALBUM'];
          trackNumber = _leadingInt(c['TRACKNUMBER']);
          year = _leadingInt(c['DATE'] ?? c['YEAR']);
          lyrics = c['LYRICS'] ?? c['UNSYNCEDLYRICS'];
        case 6:
          picture = _flacPicture(block);
      }
    }
    if (header & 0x80 != 0) break; // last metadata block
    pos = end;
  }

  return EmbeddedTags(
    title: title,
    artist: artist,
    albumArtist: albumArtist,
    album: album,
    trackNumber: trackNumber,
    year: year,
    duration: duration,
    lyrics: lyrics,
    picture: picture,
  );
}

Duration? _streamInfoDuration(Uint8List b) {
  if (b.length < 18) return null;
  final sampleRate = (b[10] << 12) | (b[11] << 4) | (b[12] >> 4);
  final totalSamples =
      ((b[13] & 0x0f) << 32) | (b[14] << 24) | (b[15] << 16) | (b[16] << 8) | b[17];
  if (sampleRate == 0 || totalSamples == 0) return null;
  return Duration(microseconds: totalSamples * 1000000 ~/ sampleRate);
}

Map<String, String> _vorbisComments(Uint8List b) {
  final view = ByteData.sublistView(b);
  final result = <String, String>{};
  try {
    var p = 4 + view.getUint32(0, Endian.little); // skip vendor string
    final count = view.getUint32(p, Endian.little);
    p += 4;
    for (var i = 0; i < count; i++) {
      final length = view.getUint32(p, Endian.little);
      final entry = utf8.decode(Uint8List.sublistView(b, p + 4, p + 4 + length), allowMalformed: true);
      p += 4 + length;
      final eq = entry.indexOf('=');
      if (eq <= 0) continue;
      // First value wins for repeated keys (e.g. multiple ARTIST entries).
      result.putIfAbsent(entry.substring(0, eq).toUpperCase(), () => entry.substring(eq + 1).trim());
    }
  } on RangeError {
    // Corrupt block: keep whatever was read.
  }
  return result;
}

EmbeddedPicture? _flacPicture(Uint8List b) {
  try {
    final view = ByteData.sublistView(b);
    var p = 4; // picture type
    final mimeLength = view.getUint32(p);
    final mime = latin1.decode(Uint8List.sublistView(b, p + 4, p + 4 + mimeLength));
    p += 4 + mimeLength;
    p += 4 + view.getUint32(p); // description
    p += 16; // width, height, depth, colours
    final dataLength = view.getUint32(p);
    return EmbeddedPicture(mime, Uint8List.fromList(Uint8List.sublistView(b, p + 4, p + 4 + dataLength)));
  } on RangeError {
    return null;
  }
}

// ---------------------------------------------------------------- ID3v2 ---

(EmbeddedTags, int) _parseId3(Uint8List data, int offset, bool truncated) {
  if (data.length < offset + 10) {
    if (truncated) return (EmbeddedTags.empty, data.length);
    throw NeedMoreData(offset + 10);
  }
  final major = data[offset + 3];
  final flags = data[offset + 5];
  final size = _syncsafe(data, offset + 6);
  final hasFooter = major == 4 && flags & 0x10 != 0;
  final end = offset + 10 + size + (hasFooter ? 10 : 0);
  if (data.length < end) {
    if (truncated) return (EmbeddedTags.empty, data.length);
    throw NeedMoreData(end);
  }
  if (major < 2 || major > 4) return (EmbeddedTags.empty, end);

  var tag = Uint8List.sublistView(data, offset + 10, offset + 10 + size);
  if (major < 4 && flags & 0x80 != 0) tag = _removeUnsync(tag);

  var p = 0;
  if (flags & 0x40 != 0 && major >= 3) {
    // Extended header: v2.3 size excludes itself, v2.4 is syncsafe and includes itself.
    p = major == 3 ? 4 + _uint32(tag, 0) : _syncsafe(tag, 0);
  }

  final idLength = major == 2 ? 3 : 4;
  final headerLength = major == 2 ? 6 : 10;
  final text = <String, String>{};
  String? lyrics;
  EmbeddedPicture? picture;
  var pictureIsFront = false;

  while (p + headerLength <= tag.length) {
    if (tag[p] == 0) break; // padding
    final id = latin1.decode(Uint8List.sublistView(tag, p, p + idLength));
    final frameSize = switch (major) {
      2 => (tag[p + 3] << 16) | (tag[p + 4] << 8) | tag[p + 5],
      3 => _uint32(tag, p + 4),
      _ => _syncsafe(tag, p + 4),
    };
    final formatFlags = major == 4 ? tag[p + 9] : 0;
    final start = p + headerLength;
    final stop = start + frameSize;
    if (stop > tag.length) break;
    p = stop;
    if (frameSize == 0) continue;

    var body = Uint8List.sublistView(tag, start, stop);
    if (major == 4) {
      if (formatFlags & 0x01 != 0 && body.length >= 4) body = Uint8List.sublistView(body, 4);
      if (formatFlags & 0x02 != 0) body = _removeUnsync(body);
    }
    // Compressed/encrypted frames are rare; skip them.
    if ((major == 3 && tag[start - 1] & 0xc0 != 0) || (major == 4 && formatFlags & 0x0c != 0)) {
      continue;
    }

    final key = _id3v22Aliases[id] ?? id;
    if (key.startsWith('T') && key != 'TXXX') {
      final value = _decodeText(body);
      if (value != null) text[key] = value;
    } else if (key == 'USLT') {
      lyrics ??= _decodeUslt(body);
    } else if (key == 'APIC' && !pictureIsFront) {
      final pic = major == 2 ? _decodePic22(body) : _decodeApic(body);
      if (pic != null) {
        picture = pic.$1;
        pictureIsFront = pic.$2 == 3;
      }
    }
  }

  final tlen = int.tryParse(text['TLEN'] ?? '');
  return (
    EmbeddedTags(
      title: text['TIT2'],
      artist: text['TPE1'],
      albumArtist: text['TPE2'],
      album: text['TALB'],
      trackNumber: _leadingInt(text['TRCK']),
      year: _leadingInt(text['TDRC'] ?? text['TYER']),
      duration: tlen == null || tlen <= 0 ? null : Duration(milliseconds: tlen),
      lyrics: lyrics,
      picture: picture,
    ),
    end,
  );
}

const _id3v22Aliases = {
  'TT2': 'TIT2', 'TP1': 'TPE1', 'TP2': 'TPE2', 'TAL': 'TALB', 'TRK': 'TRCK',
  'TYE': 'TYER', 'TLE': 'TLEN', 'ULT': 'USLT', 'PIC': 'APIC',
};

String? _decodeText(Uint8List body) {
  if (body.isEmpty) return null;
  final value = _decodeString(body[0], Uint8List.sublistView(body, 1));
  // v2.4 separates multiple values with NULs; keep the first.
  final first = value.split('\u0000').first.trim();
  return first.isEmpty ? null : first;
}

String? _decodeUslt(Uint8List body) {
  if (body.length < 5) return null;
  final encoding = body[0];
  final descEnd = _terminator(body, 4, encoding);
  if (descEnd < 0) return null;
  final text = _decodeString(encoding, Uint8List.sublistView(body, descEnd + _terminatorLength(encoding)))
      .replaceAll('\u0000', '')
      .trim();
  return text.isEmpty ? null : text;
}

(EmbeddedPicture, int)? _decodeApic(Uint8List body) {
  final encoding = body.isEmpty ? 0 : body[0];
  final mimeEnd = body.indexOf(0, 1);
  if (mimeEnd < 0 || mimeEnd + 2 > body.length) return null;
  final mime = latin1.decode(Uint8List.sublistView(body, 1, mimeEnd));
  final type = body[mimeEnd + 1];
  final descEnd = _terminator(body, mimeEnd + 2, encoding);
  if (descEnd < 0) return null;
  final data = Uint8List.sublistView(body, descEnd + _terminatorLength(encoding));
  if (data.isEmpty) return null;
  return (EmbeddedPicture(mime.isEmpty ? 'image/jpeg' : mime, Uint8List.fromList(data)), type);
}

(EmbeddedPicture, int)? _decodePic22(Uint8List body) {
  if (body.length < 6) return null;
  final format = latin1.decode(Uint8List.sublistView(body, 1, 4)).toLowerCase();
  final type = body[4];
  final descEnd = _terminator(body, 5, body[0]);
  if (descEnd < 0) return null;
  final data = Uint8List.sublistView(body, descEnd + _terminatorLength(body[0]));
  return (EmbeddedPicture(format == 'png' ? 'image/png' : 'image/jpeg', Uint8List.fromList(data)), type);
}

String _decodeString(int encoding, Uint8List bytes) {
  switch (encoding) {
    case 1: // UTF-16 with BOM
    case 2: // UTF-16BE
      var bigEndian = encoding == 2;
      var start = 0;
      if (bytes.length >= 2 && encoding == 1) {
        if (bytes[0] == 0xff && bytes[1] == 0xfe) {
          bigEndian = false;
          start = 2;
        } else if (bytes[0] == 0xfe && bytes[1] == 0xff) {
          bigEndian = true;
          start = 2;
        }
      }
      final units = <int>[];
      for (var i = start; i + 1 < bytes.length; i += 2) {
        units.add(bigEndian ? (bytes[i] << 8) | bytes[i + 1] : bytes[i] | (bytes[i + 1] << 8));
      }
      return String.fromCharCodes(units);
    case 3:
      return utf8.decode(bytes, allowMalformed: true);
    default:
      return latin1.decode(bytes);
  }
}

/// Index of the string terminator starting at [from], honouring 2-byte NULs for UTF-16.
int _terminator(Uint8List b, int from, int encoding) {
  if (_terminatorLength(encoding) == 1) return b.indexOf(0, from);
  for (var i = from; i + 1 < b.length; i += 2) {
    if (b[i] == 0 && b[i + 1] == 0) return i;
  }
  return -1;
}

int _terminatorLength(int encoding) => encoding == 1 || encoding == 2 ? 2 : 1;

Uint8List _removeUnsync(Uint8List b) {
  final out = BytesBuilder(copy: false);
  for (var i = 0; i < b.length; i++) {
    out.addByte(b[i]);
    if (b[i] == 0xff && i + 1 < b.length && b[i + 1] == 0x00) i++;
  }
  return out.takeBytes();
}

int _syncsafe(Uint8List b, int p) =>
    ((b[p] & 0x7f) << 21) | ((b[p + 1] & 0x7f) << 14) | ((b[p + 2] & 0x7f) << 7) | (b[p + 3] & 0x7f);

int _uint32(Uint8List b, int p) => (b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3];

int? _leadingInt(String? s) {
  if (s == null) return null;
  final match = RegExp(r'^\s*(\d+)').firstMatch(s);
  return match == null ? null : int.tryParse(match.group(1)!);
}
