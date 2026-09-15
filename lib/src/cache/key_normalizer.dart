import 'package:collection/collection.dart';

/// Normalizes a user-supplied cache key into an [Object] with correct
/// value-based `==`/`hashCode`, so equivalent keys collide in the cache.
///
/// `String`s, other primitives, and Dart 3 `Record`s already have
/// structural equality and are returned unchanged (identity-preserving,
/// avoiding unnecessary allocation). `List`s do not have value equality by
/// default, so they are wrapped in [_ListKey], which provides deep
/// `==`/`hashCode` over the list's elements.
///
/// `null` is a valid key meaning "don't fetch" and is handled upstream by
/// the hook layer, not here.
Object normalizeKey(Object key) {
  if (key is List) {
    return _ListKey(key);
  }
  return key;
}

/// Wraps a [List] key to give it deep value equality, so two distinct list
/// instances with equal contents normalize to the same cache key.
class _ListKey {
  _ListKey(this.values);

  final List<Object?> values;

  static const _equality = DeepCollectionEquality();

  @override
  bool operator ==(Object other) {
    return other is _ListKey && _equality.equals(values, other.values);
  }

  @override
  int get hashCode => _equality.hash(values);
}
