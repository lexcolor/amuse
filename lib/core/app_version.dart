import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Version baked into the build with `--dart-define=AMUSE_VERSION=x.y.z+n`
/// (tool/deploy_web.ps1 does this). Needed on the web: package_info_plus
/// fetches version.json fresh from the server there, so a browser running a
/// cached, older bundle would otherwise report the newly deployed number.
const _compiledVersion = String.fromEnvironment('AMUSE_VERSION');

/// The app's version as set in pubspec.yaml, e.g. "1.1.0 (2)".
final appVersionProvider = FutureProvider<String>((ref) async {
  if (_compiledVersion.isNotEmpty) {
    final plus = _compiledVersion.indexOf('+');
    return plus < 0 ? _compiledVersion : '${_compiledVersion.substring(0, plus)} (${_compiledVersion.substring(plus + 1)})';
  }
  final info = await PackageInfo.fromPlatform();
  final build = info.buildNumber.isEmpty ? '' : ' (${info.buildNumber})';
  return '${info.version}$build';
});
