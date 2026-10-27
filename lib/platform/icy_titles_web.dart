import 'package:media_kit/media_kit.dart';

/// Browsers don't expose a stream's in-band (ICY) titles, so there are none.
void observeIcyTitles(Player player, void Function(String title) onTitle) {}
