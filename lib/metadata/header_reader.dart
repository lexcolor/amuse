import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/models.dart';
import 'tag_parser.dart';

/// Streams the start of a remote audio file and parses its tags, stopping as
/// soon as the parser has what it needs. Works whether or not the server
/// honours range requests, since it simply stops reading.
Future<EmbeddedTags> readRemoteTags(
  http.Client client,
  PlayableStream stream, {
  int maxBytes = 16 * 1024 * 1024,
}) async {
  final request = http.Request('GET', stream.uri)..headers.addAll(stream.headers);
  final response = await client.send(request);
  if (response.statusCode != 200 && response.statusCode != 206) {
    unawaited(response.stream.listen(null).cancel());
    throw http.ClientException('HTTP ${response.statusCode}', stream.uri);
  }
  return _readTagsFrom(response.stream, maxBytes);
}

/// Same as [readRemoteTags] for a file on this device. Reads only as much as
/// the parser asks for, and always closes the file (an open handle would
/// stop the user moving or deleting it on Windows).
Future<EmbeddedTags> readLocalTags(File file, {int maxBytes = 16 * 1024 * 1024}) async {
  final handle = await file.open();
  try {
    return await readTagsWith((_, length) => handle.read(length), maxBytes: maxBytes);
  } finally {
    await handle.close();
  }
}

/// Same as [readLocalTags] for anything that hands out the file's bytes in
/// order (Android documents). [read] returns fewer bytes only at the end.
Future<EmbeddedTags> readTagsWith(
  Future<List<int>> Function(int offset, int length) read, {
  int maxBytes = 16 * 1024 * 1024,
}) async {
  final buffer = _GrowableBuffer();
  var needed = 64 * 1024;
  while (true) {
    final chunk = await read(buffer.length, needed - buffer.length);
    buffer.add(chunk);
    final atEnd = chunk.isEmpty || buffer.length < needed;
    try {
      return parseTags(buffer.view, truncated: atEnd || buffer.length >= maxBytes);
    } on NeedMoreData catch (e) {
      if (atEnd || buffer.length >= maxBytes) return parseTags(buffer.view, truncated: true);
      needed = e.bytes.clamp(buffer.length + 1, maxBytes);
    }
  }
}

Future<EmbeddedTags> _readTagsFrom(Stream<List<int>> bytes, int maxBytes) {
  final buffer = _GrowableBuffer();
  final result = Completer<EmbeddedTags>();
  var needed = 10;
  late final StreamSubscription<List<int>> subscription;

  void finish(EmbeddedTags Function() parse) {
    if (result.isCompleted) return;
    try {
      result.complete(parse());
    } catch (e, s) {
      result.completeError(e, s);
    }
    // Don't await: cancelling a half-read HTTP response may never complete.
    unawaited(subscription.cancel());
  }

  subscription = bytes.listen(
    (chunk) {
      if (result.isCompleted) return;
      buffer.add(chunk);
      if (buffer.length < needed) return;
      try {
        final tags = parseTags(buffer.view);
        finish(() => tags);
      } on NeedMoreData catch (e) {
        needed = e.bytes;
        if (needed > maxBytes || buffer.length >= maxBytes) {
          finish(() => parseTags(buffer.view, truncated: true));
        }
      } catch (e, s) {
        finish(() => Error.throwWithStackTrace(e, s));
      }
    },
    onError: (Object e, StackTrace s) => finish(() => Error.throwWithStackTrace(e, s)),
    onDone: () => finish(() => parseTags(buffer.view, truncated: true)),
    cancelOnError: true,
  );
  return result.future;
}

class _GrowableBuffer {
  Uint8List _bytes = Uint8List(64 * 1024);
  int length = 0;

  void add(List<int> chunk) {
    if (length + chunk.length > _bytes.length) {
      var capacity = _bytes.length * 2;
      while (capacity < length + chunk.length) {
        capacity *= 2;
      }
      _bytes = Uint8List(capacity)..setRange(0, length, _bytes);
    }
    _bytes.setRange(length, length + chunk.length, chunk);
    length += chunk.length;
  }

  Uint8List get view => Uint8List.sublistView(_bytes, 0, length);
}

/// Limits how many async jobs run at once.
class Pool {
  Pool(this.size);

  final int size;
  int _active = 0;
  final _waiting = <Completer<void>>[];

  Future<T> run<T>(Future<T> Function() job) async {
    if (_active >= size) {
      final slot = Completer<void>();
      _waiting.add(slot);
      await slot.future;
    }
    _active++;
    try {
      return await job();
    } finally {
      _active--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }
}
