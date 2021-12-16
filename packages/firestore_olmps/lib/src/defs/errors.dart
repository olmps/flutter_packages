class FirestoreDatabaseError extends Error {
  FirestoreDatabaseError(this.message, [this.origin]);

  final String message;
  final Object? origin;

  String toString() => '$message\nOrigin: ${origin?.toString()}';
}

class TransactionError extends Error {
  TransactionError(this.message, [this.origin]);

  final String message;
  final Object? origin;

  String toString() => '$message\nOrigin: ${origin?.toString()}';
}