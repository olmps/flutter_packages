class AuthenticationException implements Exception {
  AuthenticationException(this.message, {this.origin});

  final String message;
  final Object? origin;

  String toString() => '$message\nOrigin: ${origin?.toString()}';
}

class FirebaseAuthenticationException extends AuthenticationException {
  FirebaseAuthenticationException(String message, {required this.firebaseCode, Object? origin}) : super(message);

  final String firebaseCode;

  String toString() => 'Firebase Code: $firebaseCode.\n${super.toString()}';
}

class UserCancelledAuthenticationException extends AuthenticationException {
  UserCancelledAuthenticationException({required this.socialProvider})
      : super('User cancelled the sign in with the social provider $socialProvider');

  final String socialProvider;
}
