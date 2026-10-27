import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../core/models.dart';

/// Routes the lock screen's and media keys' buttons to the player.
void bindMediaSessionActions({
  required void Function() play,
  required void Function() pause,
  required void Function() next,
  required void Function() previous,
}) {
  final session = web.window.navigator.mediaSession;
  session
    ..setActionHandler('play', play.toJS)
    ..setActionHandler('pause', pause.toJS)
    ..setActionHandler('nexttrack', next.toJS)
    ..setActionHandler('previoustrack', previous.toJS);
}

/// Shows [track] on the lock screen and in the OS media controls.
void showNowPlaying(Track? track) {
  final session = web.window.navigator.mediaSession;
  if (track == null) {
    session.metadata = null;
    return;
  }
  session.metadata = web.MediaMetadata(web.MediaMetadataInit(
    title: track.title,
    artist: track.artist ?? '',
    album: track.album ?? '',
    artwork: [
      if (track.artworkUrl != null) web.MediaImage(src: track.artworkUrl!),
      web.MediaImage(src: 'icons/Icon-512.png', sizes: '512x512', type: 'image/png'),
    ].toJS,
  ));
}

void setMediaSessionPlaying(bool playing) =>
    web.window.navigator.mediaSession.playbackState = playing ? 'playing' : 'paused';
