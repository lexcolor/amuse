import '../core/models.dart';

/// Lock-screen and media-key integration for the web build. Desktop builds
/// don't publish one yet.
void bindMediaSessionActions({
  required void Function() play,
  required void Function() pause,
  required void Function() next,
  required void Function() previous,
}) {}

void showNowPlaying(Track? track) {}

void setMediaSessionPlaying(bool playing) {}
