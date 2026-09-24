/// Options specific to `useSwrInfinite`, on top of the regular [SwrConfig][].
///
/// Hook-level only (not part of `SwrConfig`), with React SWR's defaults.
class SwrInfiniteOptions {
  const SwrInfiniteOptions({
    this.initialSize = 1,
    this.revalidateAll = false,
    this.revalidateFirstPage = true,
    this.persistSize = false,
    this.parallel = false,
  }) : assert(initialSize >= 1, 'initialSize must be at least 1');

  /// How many pages a list starts with the first time it's loaded.
  final int initialSize;

  /// Whether every revalidation refetches every page, instead of only the
  /// ones not cached yet (plus the first, per [revalidateFirstPage]).
  final bool revalidateAll;

  /// Whether every revalidation of an already-loaded list refetches the
  /// first page, so new items at the top show up.
  final bool revalidateFirstPage;

  /// Whether the page count carries over when the first page's key changes
  /// (e.g. a new search query). When `false`, the new list starts at
  /// [initialSize].
  final bool persistSize;

  /// Whether pages are fetched all at once instead of one after another.
  /// `getKey` then always receives `null` as `previousPageData`, so only
  /// use it for APIs where page keys don't depend on earlier pages.
  final bool parallel;
}
