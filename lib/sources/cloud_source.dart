import '../core/models.dart';
import 'auth/loopback_oauth.dart';
import 'music_source.dart';

/// A [MusicSource] that needs the user to sign in to an account.
abstract class CloudSource implements MusicSource {
  LoopbackOAuth get auth;

  /// Button label for the sign-in action, e.g. "Sign in with Google".
  String get signInLabel;

  /// The `--dart-define` that supplies this source's client ID.
  String get clientIdDefine;
}

/// What the Music folder is called in common languages, lower-cased.
const musicFolderNames = {
  'music',
  'my music',
  'música',
  'musica',
  'mi música',
  'minha música',
  'musique',
  'ma musique',
  'musik',
  'meine musik',
  'muziek',
  'musikk',
  'musiikki',
  'muzyka',
  'hudba',
  'zene',
  'muzică',
  'muzica',
  'glazba',
  'glasba',
  'muzika',
  'mūzika',
  'muusika',
  'müzik',
  'muzik',
  'nhạc',
  'музыка',
  'музика',
  'μουσική',
  'מוזיקה',
  'موسيقى',
  'الموسيقى',
  'संगीत',
  'เพลง',
  '音乐',
  '音樂',
  'ミュージック',
  '음악',
};

/// Narrows a cloud drive's root to its Music folder(s). A single match is
/// opened directly, so the drive starts inside it.
Future<FolderListing> musicRootOf(CloudSource source) async {
  final root = await source.list(null);
  final music = [
    for (final f in root.folders)
      if (f.isMusicLibrary || musicFolderNames.contains(f.name.trim().toLowerCase())) f,
  ];
  if (music.length == 1 && root.tracks.isEmpty) return source.list(music.single.id);
  return FolderListing(folders: music, tracks: root.tracks);
}
