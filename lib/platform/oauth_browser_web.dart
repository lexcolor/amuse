import 'dart:async';

import 'package:web/web.dart' as web;

import '../sources/auth/loopback_oauth.dart';

/// Sends this page to the provider's sign-in, which redirects back to the
/// app's own address. The navigation happens in the same window so an
/// installed PWA (notably on iOS) gets the callback rather than a browser tab.
/// Never completes: the response arrives on the next load via [redirectParams].
Future<Map<String, String>> openAuthorization(
  OAuthConfig config,
  Future<Uri> Function(String redirectUri) authorizeUrl,
) async {
  final location = web.window.location;
  final url = await authorizeUrl('${location.origin}${location.pathname}');
  web.window.location.assign(url.toString());
  return Completer<Map<String, String>>().future;
}

/// The OAuth callback parameters this page was loaded with, if any.
Map<String, String>? redirectParams() {
  final params = Uri.parse(web.window.location.href).queryParameters;
  return params.containsKey('state') ? params : null;
}

/// Drops the callback parameters from the address bar (and from history).
void clearRedirectParams() {
  final location = web.window.location;
  web.window.history.replaceState(null, '', '${location.pathname}${location.hash}');
}
