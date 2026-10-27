import '../core/models.dart';

/// A place music can be browsed and streamed from (a cloud drive, a radio
/// directory, a demo catalogue...). The player and UI only talk to this
/// interface, so new providers plug in without touching the rest of the app.
abstract class MusicSource {
  String get id;
  String get displayName;

  /// Lists a folder. `null` means the source's root.
  Future<FolderListing> list(String? folderId);

  /// Resolves a fresh, streamable URL for [track]. Called right before
  /// playback because cloud links are typically short-lived.
  Future<PlayableStream> resolve(Track track);
}

/// A source that can list every track under a folder in one go, faster than
/// opening each sub-folder.
abstract class DeepListing {
  /// Every track anywhere below [folderId], in batches as they arrive.
  Stream<List<Track>> tracksUnder(String folderId);
}

/// Every track in [listing] and anywhere below its folders, in batches as
/// they're found, so playback can start before a large library is covered.
/// Folders that fail to load are skipped.
Stream<List<Track>> tracksUnder(MusicSource source, FolderListing listing) async* {
  if (listing.tracks.isNotEmpty) yield listing.tracks;
  for (final folder in listing.folders) {
    if (source is DeepListing) {
      var found = false;
      try {
        await for (final batch in (source as DeepListing).tracksUnder(folder.id)) {
          found = true;
          yield batch;
        }
        continue;
      } catch (_) {
        // Fall back to opening the folders one by one, unless that would
        // repeat tracks already queued.
        if (found) continue;
      }
    }
    yield* _walk(source, folder);
  }
}

Stream<List<Track>> _walk(MusicSource source, Folder root) async* {
  final pending = [root];
  while (pending.isNotEmpty) {
    // A few folders at a time: fast enough without hammering the server.
    final round = [for (var i = 0; i < 4 && pending.isNotEmpty; i++) pending.removeAt(0)];
    final listings = await Future.wait(round.map((f) async {
      try {
        return await source.list(f.id);
      } catch (_) {
        return const FolderListing(folders: [], tracks: []);
      }
    }));
    for (final listing in listings) {
      pending.addAll(listing.folders);
      if (listing.tracks.isNotEmpty) yield listing.tracks;
    }
  }
}
