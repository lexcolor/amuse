import 'dart:async';

import 'package:media_kit/media_kit.dart';

/// Reports the song titles internet radio streams announce in-band (ICY).
void observeIcyTitles(Player player, void Function(String title) onTitle) {
  final platform = player.platform;
  if (platform is NativePlayer) {
    unawaited(platform.observeProperty('metadata/by-key/icy-title', (title) async => onTitle(title)));
  }
}
