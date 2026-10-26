import '../core/models.dart';
import 'music_source.dart';

/// Public sample files, used to exercise the player (MP3 and FLAC streaming)
/// before any cloud account is connected.
class DemoSource implements MusicSource {
  @override
  String get id => 'demo';

  @override
  String get displayName => 'Samples';

  static const _tracks = [
    Track(
      id: 'https://filesamples.com/samples/audio/flac/sample1.flac',
      sourceId: 'demo',
      title: 'FLAC Sample One',
      artist: 'filesamples.com',
      album: 'Lossless Test',
      format: 'FLAC',
      trackNumber: 1,
    ),
    Track(
      id: 'https://filesamples.com/samples/audio/flac/sample3.flac',
      sourceId: 'demo',
      title: 'FLAC Sample Three',
      artist: 'filesamples.com',
      album: 'Lossless Test',
      format: 'FLAC',
      trackNumber: 2,
    ),
    Track(
      id: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
      sourceId: 'demo',
      title: 'Song 1',
      artist: 'SoundHelix',
      album: 'Examples',
      format: 'MP3',
      trackNumber: 1,
    ),
    Track(
      id: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
      sourceId: 'demo',
      title: 'Song 2',
      artist: 'SoundHelix',
      album: 'Examples',
      format: 'MP3',
      trackNumber: 2,
    ),
  ];

  @override
  Future<FolderListing> list(String? folderId) async =>
      const FolderListing(folders: [], tracks: _tracks);

  @override
  Future<PlayableStream> resolve(Track track) async =>
      PlayableStream(Uri.parse(track.id));
}
