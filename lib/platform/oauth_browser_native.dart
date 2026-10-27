import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import '../sources/auth/loopback_oauth.dart';

/// Opens the provider's sign-in page in the system browser and waits for it
/// to redirect back to a short-lived loopback server (RFC 8252).
Future<Map<String, String>> openAuthorization(
  OAuthConfig config,
  Future<Uri> Function(String redirectUri) authorizeUrl,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  try {
    final url = await authorizeUrl('http://${config.redirectHost}:${server.port}/');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw const OAuthException('Could not open the browser');
    }

    // Browsers may also request /favicon.ico; wait for the real callback.
    final request = await server
        .firstWhere((r) => r.uri.queryParameters.containsKey('state'))
        .timeout(const Duration(minutes: 5));
    final params = request.uri.queryParameters;
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write(_callbackPage(config.providerName, ok: params['code'] != null));
    await request.response.close();
    return params;
  } finally {
    await server.close(force: true);
  }
}

/// Only the web build comes back from sign-in through a page load.
Map<String, String>? redirectParams() => null;

void clearRedirectParams() {}

String _callbackPage(String providerName, {required bool ok}) => '''
<!doctype html><html><head><meta charset="utf-8"><title>Amuse</title>
<style>body{margin:0;height:100vh;display:grid;place-items:center;background:#0e0b16;
color:#eee;font:16px system-ui,sans-serif}h1{font-weight:600;font-size:22px}</style></head>
<body><div style="text-align:center"><h1>${ok ? '$providerName connected' : 'Sign-in failed'}</h1>
<p>You can close this tab and return to Amuse.</p></div></body></html>''';
