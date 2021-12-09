/// Metadata used to filter documents in a collection query.
class QueryFilter {
  /// Creates a new filter instance.
  /// 
  /// At least one optional filter comparison must be provided.
  QueryFilter({
    required this.field,
    this.isEqualTo,
    this.isNotEqualTo,
    this.isLessThan,
    this.isLessThanOrEqualTo,
    this.isGreaterThan,
    this.isGreaterThanOrEqualTo,
    this.arrayContains,
    this.arrayContainsAny,
    this.whereIn,
    this.whereNotIn,
    this.isNull,
  }): assert(
    isEqualTo != null || isNotEqualTo != null || isLessThan != null || isLessThanOrEqualTo != null ||
    isGreaterThan != null || isGreaterThanOrEqualTo != null || arrayContains != null || arrayContainsAny != null ||
    whereIn != null || whereNotIn != null || isNull != null, 'At least one filter must be provided');

  /// Field name to be matched.
  final String field;

  final Object? isEqualTo;
  final Object? isNotEqualTo;
  final Object? isLessThan;
  final Object? isLessThanOrEqualTo;
  final Object? isGreaterThan;
  final Object? isGreaterThanOrEqualTo;
  final Object? arrayContains;
  final List<Object?>? arrayContainsAny;
  final List<Object?>? whereIn;
  final List<Object?>? whereNotIn;
  final bool? isNull;

  @override
  String toString() {
    final filtersDescriptions = [
      if (isEqualTo != null) 'isEqualTo: $isEqualTo',
      if (isNotEqualTo != null) 'isNotEqualTo: $isNotEqualTo',
      if (isLessThan != null) 'isLessThan: $isLessThan',
      if (isLessThanOrEqualTo != null) 'isLessThanOrEqualTo: $isLessThanOrEqualTo',
      if (isGreaterThan != null) 'isGreaterThan: $isGreaterThan',
      if (isGreaterThanOrEqualTo != null) 'isGreaterThanOrEqualTo: $isGreaterThanOrEqualTo',
      if (arrayContains != null) 'arrayContains: $arrayContains',
      if (arrayContainsAny != null) 'arrayContainsAny: $arrayContainsAny',
      if (whereIn != null) 'whereIn: $whereIn',
      if (whereNotIn != null) 'whereNotIn: $whereNotIn',
      if (isNull != null) 'isNull: $isNull',
    ].reduce((result, next) => '$result; $next');
    
    return 'QueryFilter($field): $filtersDescriptions';
  }
}