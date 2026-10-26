import 'dart:async';

import '../core/models.dart';
import '../sources/music_source.dart';
import 'radio_browser.dart';

/// Live radio as a [MusicSource], so stations play through the same queue as
/// files (skipping next/previous zaps between the listed stations).
/// Browsing happens in the radio view, not through [list].
class RadioSource implements MusicSource {
  RadioSource(this.browser);

  final RadioBrowser browser;

  @override
  String get id => 'radio';

  @override
  String get displayName => 'Radio';

  @override
  Future<FolderListing> list(String? folderId) async =>
      const FolderListing(folders: [], tracks: []);

  @override
  Future<PlayableStream> resolve(Track track) async {
    unawaited(browser.click(track.id));
    return PlayableStream(Uri.parse(track.streamHint!));
  }
}
