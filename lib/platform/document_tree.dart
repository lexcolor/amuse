import 'package:flutter/services.dart';

/// One entry in an Android document folder.
class DocumentEntry {
  const DocumentEntry({required this.uri, required this.name, required this.isFolder});

  /// A `content://` document URI that stays readable under the user's grant.
  final String uri;
  final String name;
  final bool isFolder;
}

/// Folders the user granted through Android's folder picker. Reaches
/// internal storage and SD cards without a storage permission, and the
/// grant outlives the app process. Implemented in `MainActivity.kt`.
class DocumentTree {
  const DocumentTree();

  static const _channel = MethodChannel('amuse/documents');

  /// Opens the system folder picker; null if the user backs out.
  Future<({String uri, String name})?> pickFolder() async {
    final picked = await _call<Map<Object?, Object?>>('pickFolder');
    return picked == null ? null : (uri: picked['uri'] as String, name: picked['name'] as String);
  }

  Future<List<DocumentEntry>> list(String folderUri) async {
    final entries = await _call<List<Object?>>('list', {'uri': folderUri}) ?? const [];
    return [
      for (final e in entries.cast<Map<Object?, Object?>>())
        DocumentEntry(uri: e['uri'] as String, name: e['name'] as String, isFolder: e['folder'] as bool),
    ];
  }

  /// Up to [length] bytes from [offset]; fewer only at the end of the file.
  Future<Uint8List> read(String uri, int offset, int length) async =>
      await _call<Uint8List>('read', {'uri': uri, 'offset': offset, 'length': length}) ?? Uint8List(0);

  /// Gives back the grant for a folder the user removed.
  Future<void> release(String treeUri) => _call<void>('release', {'uri': treeUri});

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw DocumentAccessException(
        e.code == 'denied'
            ? 'Amuse can no longer read this folder. If it\'s on an SD card, check the card is in, '
                'or remove the folder and add it again.'
            : 'Couldn\'t open this folder',
      );
    }
  }
}

class DocumentAccessException implements Exception {
  const DocumentAccessException(this.message);

  final String message;

  @override
  String toString() => message;
}

bool isContentUri(String s) => s.startsWith('content://');
