import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import '../core/models.dart';
import '../core/providers.dart';
import '../platform/icy_titles_native.dart' if (dart.library.js_interop) '../platform/icy_titles_web.dart';
import '../platform/media_session_native.dart' if (dart.library.js_interop) '../platform/media_session_web.dart';

final playerProvider = Provider<Player>((ref) {
  final player = Player(configuration: const PlayerConfiguration(title: 'Amuse'));
  ref.onDispose(player.dispose);
  return player;
});

final positionProvider =
    StreamProvider<Duration>((ref) => ref.watch(playerProvider).stream.position);
final durationProvider =
    StreamProvider<Duration>((ref) => ref.watch(playerProvider).stream.duration);
final playingProvider =
    StreamProvider<bool>((ref) => ref.watch(playerProvider).stream.playing);
final bufferingProvider =
    StreamProvider<bool>((ref) => ref.watch(playerProvider).stream.buffering);
final volumeProvider =
    StreamProvider<double>((ref) => ref.watch(playerProvider).stream.volume);

class PlaybackState {
  const PlaybackState({this.queue = const [], this.index = -1, this.error});

  final List<Track> queue;
  final int index;
  final String? error;

  Track? get current => index >= 0 && index < queue.length ? queue[index] : null;
  bool get hasNext => index + 1 < queue.length;
  bool get hasPrevious => index > 0;
}

/// Owns the play queue. The queue is managed here rather than with
/// media_kit's playlist because cloud stream URLs expire, so each track's URL
/// is resolved only when that track starts.
class PlayerController extends Notifier<PlaybackState> {
  Player get _player => ref.read(playerProvider);
  int _loadToken = 0;

  /// Bumped whenever a new queue starts, to stop a shuffle still gathering.
  int _queueToken = 0;

  @override
  PlaybackState build() {
    final sub = ref.watch(playerProvider).stream.completed.listen((done) {
      // A radio stream that drops shouldn't jump to another station.
      if (done && state.hasNext && !(state.current?.isLive ?? false)) next();
    });
    final errors = ref.watch(playerProvider).stream.error.listen((message) {
      state = PlaybackState(queue: state.queue, index: state.index, error: message);
    });
    ref.onDispose(() {
      sub.cancel();
      errors.cancel();
    });
    return const PlaybackState();
  }

  Future<void> playQueue(List<Track> tracks, int startIndex) async {
    _queueToken++;
    state = PlaybackState(queue: tracks, index: startIndex);
    await _load();
  }

  /// Plays everything [batches] produces in random order. Starts with the
  /// first batch and shuffles later ones into the songs still to come.
  /// Returns whether anything was found to play.
  Future<bool> playShuffled(Stream<List<Track>> batches, {void Function()? onStarted}) async {
    final token = ++_queueToken;
    final random = Random();
    var started = false;
    await for (final batch in batches) {
      if (token != _queueToken) return started;
      if (batch.isEmpty) continue;
      if (!started) {
        started = true;
        onStarted?.call();
        state = PlaybackState(queue: [...batch]..shuffle(random), index: 0);
        unawaited(_load());
        continue;
      }
      final played = state.queue.sublist(0, state.index + 1);
      final upcoming = [...state.queue.sublist(state.index + 1), ...batch]..shuffle(random);
      state = PlaybackState(queue: [...played, ...upcoming], index: state.index, error: state.error);
      // The songs found so far may already have run out.
      if (_player.state.completed) unawaited(next());
    }
    return started;
  }

  Future<void> next() async {
    if (!state.hasNext) return;
    state = PlaybackState(queue: state.queue, index: state.index + 1);
    await _load();
  }

  /// Restarts the current track if past 3s, otherwise goes back one.
  /// Stations can't restart, so they always go back.
  Future<void> previous() async {
    final live = state.current?.isLive ?? false;
    if (live && !state.hasPrevious) return;
    if (!live && (_player.state.position > const Duration(seconds: 3) || !state.hasPrevious)) {
      await _player.seek(Duration.zero);
      return;
    }
    state = PlaybackState(queue: state.queue, index: state.index - 1);
    await _load();
  }

  Future<void> togglePlay() => _player.playOrPause();
  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> seek(Duration position) => _player.seek(position);
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  Future<void> _load() async {
    final track = state.current;
    if (track == null) return;
    final token = ++_loadToken;
    try {
      final stream = await ref.read(sourcesProvider)[track.sourceId]!.resolve(track);
      // A newer request (fast skipping) supersedes this one.
      if (token != _loadToken) return;
      // mpv takes local files as plain paths (no %-escaping to undo).
      final uri = stream.uri;
      final location = uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
      await _player.open(Media(location, httpHeaders: stream.headers));
    } catch (e) {
      if (token != _loadToken) return;
      state = PlaybackState(queue: state.queue, index: state.index, error: '$e');
    }
  }
}

final playerControllerProvider =
    NotifierProvider<PlayerController, PlaybackState>(PlayerController.new);

/// Song titles that internet radio streams announce in-band (ICY metadata).
final _icyTitlesProvider = Provider<Stream<String>>((ref) {
  final titles = StreamController<String>.broadcast();
  observeIcyTitles(ref.watch(playerProvider), titles.add);
  ref.onDispose(titles.close);
  return titles.stream;
});

/// What the current radio station says it's playing ("Artist - Title"),
/// or null until it announces something. Resets on every track change.
class StreamTitle extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(playerControllerProvider.select((s) => s.current));
    final sub = ref.watch(_icyTitlesProvider).listen((title) {
      final t = title.trim();
      state = t.isEmpty ? null : t;
    });
    ref.onDispose(sub.cancel);
    return null;
  }
}

final streamTitleProvider = NotifierProvider<StreamTitle, String?>(StreamTitle.new);

/// Keeps the lock screen / OS media controls in step with the player. Watched
/// by the shell so it lives as long as the app.
final mediaSessionProvider = Provider<void>((ref) {
  final controller = ref.read(playerControllerProvider.notifier);
  bindMediaSessionActions(
    play: controller.play,
    pause: controller.pause,
    next: controller.next,
    previous: controller.previous,
  );
  ref.listen(playerControllerProvider.select((s) => s.current), (_, track) => showNowPlaying(track),
      fireImmediately: true);
  ref.listen(playingProvider, (_, playing) => setMediaSessionPlaying(playing.value ?? false));
});
