class LyricLine {
  const LyricLine(this.time, this.text);

  final Duration time;
  final String text;
}

enum LyricsSource {
  /// Stored inside the user's own audio file.
  embedded,

  /// Fetched from LRCLIB (opt-in).
  online,
}

class Lyrics {
  const Lyrics({
    this.synced = const [],
    this.plain,
    this.instrumental = false,
    this.source = LyricsSource.online,
  });

  /// Time-coded lines, sorted by time. Empty when only plain text is known.
  final List<LyricLine> synced;
  final String? plain;
  final bool instrumental;
  final LyricsSource source;

  bool get isSynced => synced.isNotEmpty;

  /// Index of the line being sung at [position], or -1 before the first line.
  int lineAt(Duration position) {
    var lo = 0, hi = synced.length - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (synced[mid].time <= position) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }

  Map<String, Object?> toJson() => {
        'synced': synced.isEmpty ? null : toLrc(),
        'plain': plain,
        'instrumental': instrumental,
      };

  factory Lyrics.fromJson(Map<String, Object?> json) => Lyrics(
        synced: parseLrc(json['synced'] as String? ?? ''),
        plain: json['plain'] as String?,
        instrumental: json['instrumental'] as bool? ?? false,
      );

  String toLrc() => synced.map((l) {
        final m = l.time.inMinutes.toString().padLeft(2, '0');
        final s = (l.time.inMilliseconds % 60000 / 1000).toStringAsFixed(2).padLeft(5, '0');
        return '[$m:$s]${l.text}';
      }).join('\n');
}

final _timeTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

/// Parses LRC text (`[mm:ss.xx] line`). A line may carry several time tags.
List<LyricLine> parseLrc(String lrc) {
  final lines = <LyricLine>[];
  for (final raw in lrc.split(RegExp(r'\r?\n'))) {
    final tags = _timeTag.allMatches(raw).toList();
    if (tags.isEmpty) continue;
    final text = raw.substring(tags.last.end).trim();
    for (final t in tags) {
      final fraction = t.group(3) ?? '0';
      final ms = int.parse(fraction.padRight(3, '0').substring(0, 3));
      lines.add(LyricLine(
        Duration(minutes: int.parse(t.group(1)!), seconds: int.parse(t.group(2)!), milliseconds: ms),
        text,
      ));
    }
  }
  lines.sort((a, b) => a.time.compareTo(b.time));
  return lines;
}
