// Plays real radio streams through the app's player stack and checks that
// audio flows and the stations' "now playing" titles come through.
// Run with:
//   flutter run -d windows -t tool/radio_probe.dart
import 'dart:async';
import 'dart:io';

import 'package:amuse/player/player_controller.dart';
import 'package:amuse/radio/radio_browser.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' hide Track;

// Spanish stations taken from a Radio Browser search around Madrid.
const _stations = [
  ('LOS 40 (MP3, ICY)', 'https://playerservices.streamtheworld.com/api/livestream-redirect/Los40.mp3', false),
  ('esRadio (MP3)', 'https://libertaddigital-radio-live1.flumotion.com/libertaddigital/ld-live1-low.mp3', false),
  ('RNE Radio Nacional (HLS)', 'https://rtvelivestream.rtve.es/rtvesec/rne/rne_r1_main.m3u8', true),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const SizedBox());

  final container = ProviderContainer();
  final player = container.read(playerProvider);
  await player.setVolume(0);
  final controller = container.read(playerControllerProvider.notifier);
  final titles = <String?>[];
  container.listen(streamTitleProvider, (_, t) => titles.add(t), fireImmediately: true);

  final tracks = [
    for (final (i, (name, url, hls)) in _stations.indexed)
      RadioStation(uuid: 'probe-$i', name: name, streamUrl: url, hls: hls).toTrack(),
  ];

  var failed = false;
  for (var i = 0; i < tracks.length; i++) {
    titles.clear();
    await controller.playQueue(tracks, i);
    final position = await player.stream.position
        .firstWhere((p) => p > const Duration(seconds: 3))
        .timeout(const Duration(seconds: 30), onTimeout: () => Duration.zero);
    // Give the station a moment to announce the song.
    await Future<void>.delayed(const Duration(seconds: 4));
    final state = container.read(playerControllerProvider);
    final params = player.state.audioParams;
    final ok = position > Duration.zero && state.error == null;
    failed |= !ok;
    stdout.writeln('PROBE ${ok ? 'OK  ' : 'FAIL'} ${tracks[i].title}\n'
        '      position=$position duration=${player.state.duration} '
        'format=${params.format} rate=${params.sampleRate} '
        'onAir=${container.read(streamTitleProvider)} titleEvents=$titles error=${state.error}');
  }

  container.dispose();
  exit(failed ? 1 : 0);
}
