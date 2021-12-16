class TransactionError extends Error {
  TransactionError(this.message);
  final String message;

  @override
  String toString() => message;
}
