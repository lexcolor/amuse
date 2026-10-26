import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provided in `main` once preferences have loaded.
final sharedPreferencesProvider = Provider<SharedPreferencesWithCache>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

const _onlineLyricsKey = 'lyrics.online';
const settingsKeys = {_onlineLyricsKey};

class AppSettings {
  const AppSettings({this.onlineLyrics = false});

  /// Look up lyrics on LRCLIB when a file has none embedded. Off by default:
  /// lyrics are copyrighted, so each user opts in for themselves.
  final bool onlineLyrics;
}

class SettingsController extends Notifier<AppSettings> {
  SharedPreferencesWithCache get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() => AppSettings(onlineLyrics: _prefs.getBool(_onlineLyricsKey) ?? false);

  Future<void> setOnlineLyrics(bool enabled) async {
    state = AppSettings(onlineLyrics: enabled);
    await _prefs.setBool(_onlineLyricsKey, enabled);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
