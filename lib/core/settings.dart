import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provided in `main` once preferences have loaded.
final sharedPreferencesProvider = Provider<SharedPreferencesWithCache>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

const _onlineLyricsKey = 'lyrics.online';
const _musicFolderOnlyKey = 'library.musicFolderOnly';
const settingsKeys = {_onlineLyricsKey, _musicFolderOnlyKey};

class AppSettings {
  const AppSettings({this.onlineLyrics = false, this.musicFolderOnly = true});

  /// Look up lyrics on LRCLIB when a file has none embedded. Off by default:
  /// lyrics are copyrighted, so each user opts in for themselves.
  final bool onlineLyrics;

  /// Cloud drives open straight into their Music folder instead of showing
  /// every folder in the account.
  final bool musicFolderOnly;

  AppSettings copyWith({bool? onlineLyrics, bool? musicFolderOnly}) => AppSettings(
    onlineLyrics: onlineLyrics ?? this.onlineLyrics,
    musicFolderOnly: musicFolderOnly ?? this.musicFolderOnly,
  );
}

class SettingsController extends Notifier<AppSettings> {
  SharedPreferencesWithCache get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() => AppSettings(
    onlineLyrics: _prefs.getBool(_onlineLyricsKey) ?? false,
    musicFolderOnly: _prefs.getBool(_musicFolderOnlyKey) ?? true,
  );

  Future<void> setOnlineLyrics(bool enabled) async {
    state = state.copyWith(onlineLyrics: enabled);
    await _prefs.setBool(_onlineLyricsKey, enabled);
  }

  Future<void> setMusicFolderOnly(bool enabled) async {
    state = state.copyWith(musicFolderOnly: enabled);
    await _prefs.setBool(_musicFolderOnlyKey, enabled);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
