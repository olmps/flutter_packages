import 'package:sign_in_with_apple/sign_in_with_apple.dart' show AppleIDAuthorizationScopes;

// TODO(matuella): Doc properties
class AppleSignInConfig {
  AppleSignInConfig({
    required this.webClientId,
    required this.webRedirectUri,
    this.scopes = AppleIDAuthorizationScopes.values,
  });

  /// Available scopes that will be requested during the sign in.
  final List<AppleIDAuthorizationScopes> scopes;
  final String webClientId;
  final Uri webRedirectUri;
}

// TODO(matuella): Doc properties
class GithubSignInConfig {
  GithubSignInConfig({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUrl,
    this.scope = "user,gist,user:email",
  });

  final String clientId;
  final String clientSecret;
  final String redirectUrl;
  final String scope;
}
