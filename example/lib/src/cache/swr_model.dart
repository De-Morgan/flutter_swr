/// Registers [fromJson] for both `T` and `List<T>` in one call, so a model
/// only needs to be wired up once regardless of whether `useSwr` reads it
/// singly or as a list — pass the merged result to
/// [SharedPreferencesSwrCache.open]'s or [SqfliteSwrCache.open]'s`fromJson` map via the spread
/// operator, e.g. `{...swrModel<Product>(Product.fromJson)}`.
Map<Type, dynamic Function(Object? json)> swrModel<T>(
  T Function(Map<String, dynamic>) fromJson,
) {
  return {
    T: (j) => fromJson(j as Map<String, dynamic>),
    List<T>: (j) =>
        (j as List).map((e) => fromJson(e as Map<String, dynamic>)).toList(),
  };
}
