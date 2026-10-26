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
