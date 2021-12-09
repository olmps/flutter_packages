/// Metadata used to sort documents in a collection query.
class QuerySort {
  QuerySort({required this.field, this.descending = false});

  final String field;
  final bool descending;
}