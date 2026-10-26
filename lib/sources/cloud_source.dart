import 'auth/loopback_oauth.dart';
import 'music_source.dart';

/// A [MusicSource] that needs the user to sign in to an account.
abstract class CloudSource implements MusicSource {
  LoopbackOAuth get auth;

  /// Button label for the sign-in action, e.g. "Sign in with Google".
  String get signInLabel;

  /// The `--dart-define` that supplies this source's client ID.
  String get clientIdDefine;
}
