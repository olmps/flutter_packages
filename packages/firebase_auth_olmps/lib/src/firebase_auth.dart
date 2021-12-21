import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_auth_olmps/src/authentication_exception.dart';
import 'package:firebase_auth_olmps/src/config.dart';
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:github_sign_in/github_sign_in.dart' as github_sign_in;
import 'package:google_sign_in/google_sign_in.dart' as google_sign_in;
import 'package:sign_in_with_apple/sign_in_with_apple.dart' as sign_in_with_apple;

export 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;

/// Firebase implementation of common authentication methods.
abstract class FirebaseAuthentication {
  /// Uses the respective platform's authentication flow to sign in an user using Apple as the provider.
  /// 
  /// Throws [StateError] if this instance wasn't properly configure.
  /// 
  /// Throws [UserCancelledAuthenticationException] if the user cancelled the authentication.
  /// 
  /// Throws [FirebaseAuthenticationException] for any firebase-specific exception.
  /// 
  /// Throws [AuthenticationException] for any other error that may have occurred with the Apple provider.
  Future<void> signInWithApple();

  /// Uses the respective platform's authentication flow to sign in an user using Google as the provider.
  /// 
  /// Throws [UserCancelledAuthenticationException] if the user cancelled the authentication.
  /// 
  /// Throws [FirebaseAuthenticationException] for any firebase-specific exception.
  Future<void> signInWithGoogle();

  /// Uses the respective platform's authentication flow to sign in an user using Github as the provider.
  /// 
  /// Throws [StateError] if this instance wasn't properly configure.
  /// 
  /// Throws [UserCancelledAuthenticationException] if the user cancelled the authentication.
  /// 
  /// Throws [FirebaseAuthenticationException] for any firebase-specific exception.
  /// 
  /// Throws [AuthenticationException] for any other error that may have occurred with the Github provider.
  Future<void> signInWithGithub(BuildContext context);

  /// Signs out the current authenticated user.
  ///
  /// Does nothing if there is no authenticated user.
  Future<void> signOut();
}

class FirebaseAuthenticationImpl implements FirebaseAuthentication {
  /// Creates a new instance using `FirebaseAuth`.
  /// 
  /// All operations will reflect on the current user available a the [FirebaseAuth] instance.
  /// 
  /// To use [signInWithApple], you must pass a valid [appleConfig].
  /// 
  /// To use [signInWithGithub], you must pass a valid [githubConfig].
  FirebaseAuthenticationImpl(this._auth, {this.appleConfig, this.githubConfig});

  final firebase_auth.FirebaseAuth _auth;

  final AppleSignInConfig? appleConfig;
  final GithubSignInConfig? githubConfig;

  static const _appleProviderId = 'apple.com';
  
  @override
  Future<void> signInWithApple() async {
    final config = appleConfig;
    if (config == null) {
      throw StateError(
          'Missing configuration for apple provider. To call signInWithApple, you must provide a valid AppleSignInConfig through this instance constructor.');
    }

    try {
      const nonceLength = 32;
      const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
      final random = Random.secure();
      // Generates a cryptographically secure random nonce, to be included in a credential request
      // To prevent replay attacks with the credential returned from Apple, we include a nonce in the credential request.
      // When signing in in with Firebase, the nonce in the id token returned by Apple, is expected to match the sha256
      // hash of the returned nonce.
      final rawNonce = List.generate(nonceLength, (_) => charset[random.nextInt(charset.length)]).join();
      final hashedNonce = crypto.sha256.convert(utf8.encode(rawNonce)).toString();

      // Request credential for the currently signed in Apple account.
      final appleCredential = await sign_in_with_apple.SignInWithApple.getAppleIDCredential(
        scopes: config.scopes,
        // `WebAuthenticationOptions` is required when signing using Apple provider through Android platform. This
        // happens because the way how Sign In with Apple works in Android: it opens a WebView to the user sign-in using
        // iCloud credentials then it redirects to `_env.firestoreAuthHandlerUrl` with the auth token. iOS doesn't
        // require such information because Apple has its own way of handling with Apple Sign In auth in iOS ecosystem.
        // The `sign_in_with_apple` handles the usage of these information or not based on the running platform, so we
        // no need to take care of it
        webAuthenticationOptions: sign_in_with_apple.WebAuthenticationOptions(
          clientId: config.webClientId,
          redirectUri: config.webRedirectUri, // Endpoint functions
        ),
        nonce: hashedNonce,
      );

      String? appleDisplayName;
      if (appleCredential.givenName != null && appleCredential.familyName != null) {
        appleDisplayName = '${appleCredential.givenName} ${appleCredential.familyName}';
      }

      final credential = firebase_auth.OAuthProvider(_appleProviderId).credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
        rawNonce: rawNonce,
      );

      final userCredentials = await _auth.signInWithCredential(credential);
      final firebaseUser = userCredentials.user!;

      // If displayName != null, updates [FirebaseAuth] with its value.
      // By default, the user display name is only returned in the user first sign in. After that, future attempts of
      // sign in will only return the user identifier by Apple provider. A more in-depth discussion can be found in
      // https://github.com/firebase/firebase-ios-sdk/issues/4393
      if (appleDisplayName != null) {
        await firebaseUser.updateDisplayName(appleDisplayName);
      }
    } on sign_in_with_apple.SignInWithAppleAuthorizationException catch (exception) {
      if (exception.code == sign_in_with_apple.AuthorizationErrorCode.canceled) {
        throw UserCancelledAuthenticationException(socialProvider: 'apple');
      } else {
        throw AuthenticationException('Failed to sign in using google', origin: exception);
      }
    } on firebase_auth.FirebaseAuthException catch (firebaseException) {
      throw FirebaseAuthenticationException('Failed to sign in using google',
          firebaseCode: firebaseException.code, origin: firebaseException);
    }
  }

  @override
  Future<void> signInWithGoogle() async {
    try {
      final googleUser = await google_sign_in.GoogleSignIn().signIn();

      // `googleUser` may be null if the user cancel the sign in flow
      if (googleUser == null) {
        throw UserCancelledAuthenticationException(socialProvider: 'google');
      }

      final googleAuth = await googleUser.authentication;
      final credential =
          firebase_auth.GoogleAuthProvider.credential(idToken: googleAuth.idToken, accessToken: googleAuth.accessToken);

      await _auth.signInWithCredential(credential);
    } on AuthenticationException catch (_) {
      rethrow;
    } on firebase_auth.FirebaseAuthException catch (firebaseException) {
      throw FirebaseAuthenticationException('Failed to sign in using google',
          firebaseCode: firebaseException.code, origin: firebaseException);
    }
  }

  @override
  Future<void> signInWithGithub(BuildContext context) async {
    final config = githubConfig;
    if (config == null) {
      throw StateError(
          'Missing configuration for github provider. To call signInWithGithub, you must provide a valid GithubSignInConfig through this instance constructor.');
    }

    try {
      final githubAuth = await github_sign_in.GitHubSignIn(
        clientId: config.clientId,
        clientSecret: config.clientSecret,
        redirectUrl: config.redirectUrl,
        scope: config.scope,
      ).signIn(context);

      switch (githubAuth.status) {
        case github_sign_in.GitHubSignInResultStatus.ok:
          final credential = firebase_auth.GithubAuthProvider.credential(githubAuth.token!);
          await _auth.signInWithCredential(credential);
          break;
        case github_sign_in.GitHubSignInResultStatus.cancelled:
          throw UserCancelledAuthenticationException(socialProvider: 'github');
        case github_sign_in.GitHubSignInResultStatus.failed:
          throw AuthenticationException('Failed to sign in using github', origin: githubAuth.errorMessage);
      }
    } on AuthenticationException catch (_) {
      rethrow;
    } on firebase_auth.FirebaseAuthException catch (firebaseException) {
      throw FirebaseAuthenticationException('Failed to sign in using github',
          firebaseCode: firebaseException.code, origin: firebaseException);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();
}
