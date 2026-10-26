import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../radio/radio_browser.dart';
import '../radio/radio_source.dart';
import '../sources/auth/loopback_oauth.dart';
import '../sources/cloud_source.dart';
import '../sources/demo_source.dart';
import '../sources/folders/folders_source.dart';
import '../sources/folders/locations.dart';
import '../sources/google_drive/google_drive_source.dart';
import '../sources/music_source.dart';
import '../sources/onedrive/onedrive_auth.dart';
import '../sources/onedrive/onedrive_source.dart';
import 'models.dart';

/// Every source, in sidebar order.
final sourcesProvider = Provider<Map<String, MusicSource>>((ref) {
  final sources = <MusicSource>[
    OneDriveSource(LoopbackOAuth(oneDriveOAuth)),
    GoogleDriveSource(LoopbackOAuth(googleDriveOAuth)),
    FoldersSource(() => ref.read(locationsProvider)),
    DemoSource(),
    RadioSource(RadioBrowser()),
  ];
  return {for (final s in sources) s.id: s};
});

/// Whether a cloud source has a stored session. Exposes sign-in / sign-out.
class CloudSession extends AsyncNotifier<bool> {
  CloudSession(this.sourceId);

  final String sourceId;

  LoopbackOAuth get _auth => (ref.read(sourcesProvider)[sourceId]! as CloudSource).auth;

  @override
  Future<bool> build() => _auth.hasSession();

  Future<void> signIn() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _auth.signIn();
      return true;
    });
    ref.invalidate(folderListingProvider);
  }

  Future<void> signOut() async {
    await _auth.signOut();
    ref.invalidate(folderListingProvider);
    ref.read(browseProvider.notifier).reset();
    state = const AsyncData(false);
  }
}

final cloudSessionProvider =
    AsyncNotifierProvider.family<CloudSession, bool, String>(CloudSession.new);

/// Which source is open in the browser, and the folder path within it.
class BrowseState {
  const BrowseState({required this.sourceId, this.path = const []});

  final String sourceId;
  final List<Folder> path;

  String? get folderId => path.isEmpty ? null : path.last.id;
}

class BrowseController extends Notifier<BrowseState> {
  @override
  /// Opens the first cloud source that's set up, else the samples.
  BrowseState build() {
    final sources = ref.read(sourcesProvider).values;
    final configured = sources.whereType<CloudSource>().where((s) => s.auth.isConfigured);
    return BrowseState(sourceId: configured.isEmpty ? 'demo' : configured.first.id);
  }

  void openSource(String sourceId) => state = BrowseState(sourceId: sourceId);

  void openFolder(Folder folder) =>
      state = BrowseState(sourceId: state.sourceId, path: [...state.path, folder]);

  /// Jumps back to the path depth [depth] (0 = source root).
  void popTo(int depth) => state =
      BrowseState(sourceId: state.sourceId, path: state.path.sublist(0, depth));

  void reset() => state = BrowseState(sourceId: state.sourceId);
}

final browseProvider = NotifierProvider<BrowseController, BrowseState>(BrowseController.new);

final folderListingProvider =
    FutureProvider.family<FolderListing, (String, String?)>((ref, key) {
  final (sourceId, folderId) = key;
  return ref.watch(sourcesProvider)[sourceId]!.list(folderId);
});
