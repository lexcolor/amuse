import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../platform/document_tree.dart';
import 'folders_source.dart';

const _locationsKey = 'folders.locations';
const locationsPrefsKeys = {_locationsKey};

enum LocationKind {
  /// A folder on this device or a network share.
  folder,

  /// A web page listing files and sub-folders.
  webFolder,

  /// A single song or stream.
  link,
}

class SavedLocation {
  const SavedLocation({required this.kind, required this.uri, required this.name, this.isLive = false});

  factory SavedLocation.fromJson(Map<String, Object?> json) => SavedLocation(
        kind: LocationKind.values.byName(json['kind'] as String),
        uri: json['uri'] as String,
        name: json['name'] as String,
        isLive: json['live'] as bool? ?? false,
      );

  final LocationKind kind;

  /// A path (or, on Android, a `content:` folder grant) for
  /// [LocationKind.folder]; a URL (web or `file:`) otherwise.
  final String uri;
  final String name;

  /// For links: an endless stream (internet radio) rather than a file.
  final bool isLive;

  Map<String, Object?> toJson() => {'kind': kind.name, 'uri': uri, 'name': name, 'live': isLive};
}

class LocationException implements Exception {
  const LocationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Works out what the user pasted or picked: a folder path, a web folder, or
/// a link to a song or stream. When a web address is ambiguous it's added as
/// a playable link and the player gets the final say.
Future<SavedLocation> inspectLocation(String input, {http.Client? client}) async {
  // Windows' "Copy as path" wraps paths in quotes.
  var text = input.trim();
  if (text.length > 1 && text.startsWith('"') && text.endsWith('"')) {
    text = text.substring(1, text.length - 1).trim();
  }
  if (text.isEmpty) throw const LocationException('Enter a folder or a web address.');

  if (isWebAddress(text)) return _inspectWeb(Uri.parse(text), client ?? http.Client());

  final path = text.startsWith('file:') ? Uri.parse(text).toFilePath() : text;
  if (await Directory(path).exists()) {
    final trimmed = path.length > 3 ? path.replaceAll(RegExp(r'[\\/]+$'), '') : path;
    final name = trimmed.split(RegExp(r'[\\/]')).lastWhere((s) => s.isNotEmpty, orElse: () => trimmed);
    return SavedLocation(kind: LocationKind.folder, uri: trimmed, name: name);
  }
  if (await File(path).exists()) {
    final name = path.split(RegExp(r'[\\/]')).last;
    if (!audioExtensions.contains(extensionOf(name))) {
      throw LocationException('“$name” isn\'t an audio file Amuse can play.');
    }
    return SavedLocation(kind: LocationKind.link, uri: Uri.file(path).toString(), name: stripExtension(name));
  }
  throw LocationException('Couldn\'t find “$text” on this device.');
}

Future<SavedLocation> _inspectWeb(Uri uri, http.Client client) async {
  final segments = uri.pathSegments.where((s) => s.isNotEmpty);
  final lastSegment = segments.isEmpty ? uri.host : segments.last;
  final ext = extensionOf(lastSegment);

  final http.StreamedResponse response;
  try {
    // GET rather than HEAD: plenty of servers reject HEAD. Only headers are read.
    response = await client.send(http.Request('GET', uri)..headers['Icy-MetaData'] = '1')
        .timeout(const Duration(seconds: 15));
  } on Exception catch (e) {
    throw LocationException('Couldn\'t reach ${uri.host}: $e');
  }
  unawaited(response.stream.listen(null).cancel());
  if (response.statusCode >= 400) {
    throw LocationException('${uri.host} answered ${response.statusCode}. Is the address right, and public?');
  }

  final type = (response.headers['content-type'] ?? '').toLowerCase();
  if (type.startsWith('text/html') && !audioExtensions.contains(ext)) {
    return SavedLocation(kind: LocationKind.webFolder, uri: uri.toString(), name: lastSegment);
  }
  // Radio streams announce themselves with icy-* headers or have no length;
  // stations also hand out playlist files that point at the stream.
  final playlist = const {'m3u', 'm3u8', 'pls'}.contains(ext) || type.contains('mpegurl') || type.contains('scpls');
  final live = playlist ||
      response.headers.keys.any((h) => h.startsWith('icy-')) ||
      (response.contentLength == null && !audioExtensions.contains(ext));
  final name = live ? (response.headers['icy-name']?.trim() ?? lastSegment) : stripExtension(lastSegment);
  return SavedLocation(kind: LocationKind.link, uri: uri.toString(), name: name.isEmpty ? uri.host : name, isLive: live);
}

/// The user's saved folders and links, in the order they were added.
class LocationsController extends Notifier<List<SavedLocation>> {
  SharedPreferencesWithCache get _prefs => ref.read(sharedPreferencesProvider);

  @override
  List<SavedLocation> build() {
    final saved = <SavedLocation>[];
    for (final s in _prefs.getStringList(_locationsKey) ?? const <String>[]) {
      try {
        saved.add(SavedLocation.fromJson(jsonDecode(s) as Map<String, Object?>));
      } catch (_) {
        // Skip a corrupt entry rather than losing the rest.
      }
    }
    return saved;
  }

  /// Adds [location], replacing any earlier entry for the same place.
  void add(SavedLocation location) =>
      _save([for (final l in state) if (l.uri != location.uri) l, location]);

  void remove(String uri) {
    _save([for (final l in state) if (l.uri != uri) l]);
    if (isContentUri(uri)) unawaited(const DocumentTree().release(uri).catchError((_) {}));
  }

  void _save(List<SavedLocation> locations) {
    state = locations;
    _prefs.setStringList(_locationsKey, [for (final l in locations) jsonEncode(l.toJson())]);
    ref.invalidate(folderListingProvider(('folders', null)));
  }
}

final locationsProvider =
    NotifierProvider<LocationsController, List<SavedLocation>>(LocationsController.new);
