import '../auth/loopback_oauth.dart';

/// Azure "Application (client) ID", supplied at build time:
/// `flutter run --dart-define=ONEDRIVE_CLIENT_ID=<guid>`
const oneDriveClientId = String.fromEnvironment('ONEDRIVE_CLIENT_ID');

const oneDriveOAuth = OAuthConfig(
  providerName: 'OneDrive',
  clientId: oneDriveClientId,
  // Personal Microsoft accounts (OneDrive Personal).
  authorizeUrl: 'https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize',
  tokenUrl: 'https://login.microsoftonline.com/consumers/oauth2/v2.0/token',
  scopes: 'Files.Read User.Read offline_access',
  storageKey: 'onedrive.refresh_token',
  extraAuthorizeParams: {'response_mode': 'query', 'prompt': 'select_account'},
  sendScopeToTokenEndpoint: true,
);
