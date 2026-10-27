import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../platform/oauth_browser_native.dart'
    if (dart.library.js_interop) '../../platform/oauth_browser_web.dart';

/// Endpoints and app credentials for one OAuth provider.
class OAuthConfig {
  const OAuthConfig({
    required this.providerName,
    required this.clientId,
    required this.authorizeUrl,
    required this.tokenUrl,
    required this.scopes,
    required this.storageKey,
    this.clientSecret = '',
    this.redirectHost = 'localhost',
    this.extraAuthorizeParams = const {},
    this.sendScopeToTokenEndpoint = false,
  });

  /// Shown on the browser page after sign-in, e.g. "OneDrive".
  final String providerName;
  final String clientId;

  /// Installed-app secrets aren't confidential (they ship in the binary);
  /// some providers still expect one alongside PKCE.
  final String clientSecret;
  final String authorizeUrl;
  final String tokenUrl;
  final String scopes;

  /// Secure-storage key for the refresh token.
  final String storageKey;

  /// Host of the loopback redirect URI, as registered with the provider.
  final String redirectHost;
  final Map<String, String> extraAuthorizeParams;
  final bool sendScopeToTokenEndpoint;

  bool get isConfigured => clientId.isNotEmpty;
}

/// OAuth 2.0 authorization-code + PKCE. Desktop builds use the system browser
/// and a loopback redirect (RFC 8252); the web build redirects the page itself
/// and finishes signing in when it loads again. Refresh tokens are kept in the
/// OS secure store (browser storage on the web).
class LoopbackOAuth {
  LoopbackOAuth(this.config, {http.Client? client, FlutterSecureStorage? storage})
      : _http = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  final OAuthConfig config;
  final http.Client _http;
  final FlutterSecureStorage _storage;

  String? _accessToken;
  DateTime _expiresAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isConfigured => config.isConfigured;

  Future<bool> hasSession() async {
    if (!isConfigured) return false;
    await _completeRedirect();
    return await _storage.read(key: config.storageKey) != null;
  }

  Future<void> signIn() async {
    if (!isConfigured) throw StateError('${config.providerName} client ID is not set');

    final verifier = _randomString(64);
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
    final state = _randomString(24);

    late String redirectUri;
    final params = await openAuthorization(config, (uri) async {
      redirectUri = uri;
      // The web build leaves the page to sign in; remember what to check
      // the response against when it comes back.
      await _storage.write(
        key: _pendingKey,
        value: jsonEncode({'state': state, 'verifier': verifier, 'redirectUri': uri}),
      );
      return Uri.parse(config.authorizeUrl).replace(queryParameters: {
        'client_id': config.clientId,
        'response_type': 'code',
        'redirect_uri': uri,
        'scope': config.scopes,
        'state': state,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        ...config.extraAuthorizeParams,
      });
    });
    await _storage.delete(key: _pendingKey);
    await _redeem(params, state: state, verifier: verifier, redirectUri: redirectUri);
  }

  /// Web: finishes a sign-in this page was redirected back from.
  Future<void> _completeRedirect() async {
    final params = redirectParams();
    if (params == null) return;
    final pending = await _storage.read(key: _pendingKey);
    if (pending == null) {
      // On iOS the provider can send the response to Safari rather than the
      // installed app, which keeps separate storage.
      clearRedirectParams();
      throw OAuthException('Sign-in finished in a different browser window. Open Amuse from '
          'your Home Screen and sign in to ${config.providerName} there.');
    }
    final saved = jsonDecode(pending) as Map<String, dynamic>;
    // Another provider's response.
    if (params['state'] != saved['state']) return;

    clearRedirectParams();
    await _storage.delete(key: _pendingKey);
    await _redeem(
      params,
      state: saved['state'] as String,
      verifier: saved['verifier'] as String,
      redirectUri: saved['redirectUri'] as String,
    );
  }

  Future<void> _redeem(
    Map<String, String> params, {
    required String state,
    required String verifier,
    required String redirectUri,
  }) async {
    if (params['error'] != null) {
      throw OAuthException(params['error_description'] ?? params['error']!);
    }
    if (params['state'] != state || params['code'] == null) {
      throw const OAuthException('Invalid sign-in response');
    }
    await _tokenRequest({
      'grant_type': 'authorization_code',
      'code': params['code']!,
      'redirect_uri': redirectUri,
      'code_verifier': verifier,
    });
  }

  String get _pendingKey => '${config.storageKey}.pending';

  /// Returns a valid access token, refreshing it when close to expiry.
  Future<String> accessToken() async {
    final token = _accessToken;
    if (token != null && DateTime.now().isBefore(_expiresAt)) return token;

    final refresh = await _storage.read(key: config.storageKey);
    if (refresh == null) throw const OAuthException('Not signed in');
    await _tokenRequest({'grant_type': 'refresh_token', 'refresh_token': refresh});
    return _accessToken!;
  }

  Future<void> signOut() async {
    _accessToken = null;
    await _storage.delete(key: config.storageKey);
  }

  Future<void> _tokenRequest(Map<String, String> body) async {
    final response = await _http.post(
      Uri.parse(config.tokenUrl),
      body: {
        'client_id': config.clientId,
        if (config.clientSecret.isNotEmpty) 'client_secret': config.clientSecret,
        if (config.sendScopeToTokenEndpoint) 'scope': config.scopes,
        ...body,
      },
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      if (json['error'] == 'invalid_grant') await signOut();
      throw OAuthException(
          json['error_description'] as String? ?? 'Token request failed (${response.statusCode})');
    }
    _accessToken = json['access_token'] as String;
    // Refresh a minute early so in-flight requests don't race the expiry.
    _expiresAt = DateTime.now()
        .add(Duration(seconds: (json['expires_in'] as num).toInt() - 60));
    final refresh = json['refresh_token'] as String?;
    if (refresh != null) await _storage.write(key: config.storageKey, value: refresh);
  }

  static String _randomString(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
  }
}

class OAuthException implements Exception {
  const OAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
