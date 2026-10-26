// Smoke test for the audio engine: streams a remote FLAC and MP3, then a FLAC
// from a local server that (like Google Drive) rejects requests without an
// Authorization header, including the range requests issued when seeking.
// Run with:
//   flutter run -d windows -t tool/playback_probe.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';

const _flacUrl = 'https://filesamples.com/samples/audio/flac/sample1.flac';
const _urls = [
  _flacUrl,
  'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const SizedBox());

  final player = Player();
  await player.setVolume(0);
  var failed = false;

  Future<Duration> playFor(Media media, Duration until) async {
    await player.open(media);
    return player.stream.position
        .firstWhere((p) => p > until)
        .timeout(const Duration(seconds: 30), onTimeout: () => Duration.zero);
  }

  for (final url in _urls) {
    final errors = <String>[];
    final sub = player.stream.error.listen(errors.add);
    final position = await playFor(Media(url), const Duration(seconds: 2));
    final params = player.state.audioParams;
    final ok = position > Duration.zero && errors.isEmpty;
    failed |= !ok;
    stdout.writeln('PROBE ${ok ? 'OK  ' : 'FAIL'} $url\n'
        '      duration=${player.state.duration} position=$position '
        'format=${params.format} rate=${params.sampleRate} channels=${params.channelCount} '
        'errors=$errors');
    await sub.cancel();
  }

  // Authenticated streaming + seeking.
  final bytes = (await http.get(Uri.parse(_flacUrl))).bodyBytes;
  final server = await _AuthServer.start(bytes, token: 'probe-token');
  final errors = <String>[];
  final sub = player.stream.error.listen(errors.add);
  final position = await playFor(
    Media('http://127.0.0.1:${server.port}/song.flac', httpHeaders: {'Authorization': 'Bearer probe-token'}),
    const Duration(seconds: 1),
  );
  await player.seek(const Duration(seconds: 90));
  final afterSeek = await player.stream.position
      .firstWhere((p) => p > const Duration(seconds: 91))
      .timeout(const Duration(seconds: 30), onTimeout: () => Duration.zero);
  final ok = position > Duration.zero &&
      afterSeek > Duration.zero &&
      server.rejected == 0 &&
      server.rangeRequests > 0 &&
      errors.isEmpty;
  failed |= !ok;
  stdout.writeln('PROBE ${ok ? 'OK  ' : 'FAIL'} auth-header stream with seek\n'
      '      requests=${server.requests} rangeRequests=${server.rangeRequests} '
      'rejected=${server.rejected} afterSeek=$afterSeek errors=$errors');
  await sub.cancel();
  await server.close();

  await player.dispose();
  exit(failed ? 1 : 0);
}

/// Serves one file with HTTP range support, only to requests bearing [token].
class _AuthServer {
  _AuthServer._(this._server, this._bytes, this._token) {
    _server.listen(_handle);
  }

  static Future<_AuthServer> start(List<int> bytes, {required String token}) async =>
      _AuthServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0), bytes, token);

  final HttpServer _server;
  final List<int> _bytes;
  final String _token;
  int requests = 0, rangeRequests = 0, rejected = 0;

  int get port => _server.port;

  Future<void> _handle(HttpRequest request) async {
    requests++;
    final response = request.response..headers.set('Accept-Ranges', 'bytes');
    if (request.headers.value('authorization') != 'Bearer $_token') {
      rejected++;
      response.statusCode = 401;
      return response.close();
    }
    var start = 0, end = _bytes.length - 1;
    final range = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(request.headers.value('range') ?? '');
    if (range != null) {
      start = int.parse(range.group(1)!);
      if (range.group(2)!.isNotEmpty) end = int.parse(range.group(2)!);
      if (start > 0) rangeRequests++;
      response
        ..statusCode = 206
        ..headers.set('Content-Range', 'bytes $start-$end/${_bytes.length}');
    }
    response.headers
      ..contentType = ContentType('audio', 'flac')
      ..contentLength = end - start + 1;
    try {
      // Throttle to ~1.3 MB/s, like a real connection, so a far seek can't
      // be served from what the player already buffered.
      for (var i = start; i <= end; i += 64 * 1024) {
        response.add(_bytes.sublist(i, (i + 64 * 1024).clamp(0, end + 1)));
        await response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await response.close();
    } catch (_) {
      // Player closed the connection early (normal when seeking).
    }
  }

  Future<void> close() => _server.close(force: true);
}
