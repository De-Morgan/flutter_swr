## 0.1.0

Initial release.

* `useSwr` hook: stale-while-revalidate data fetching with request deduplication and
  automatic revalidation.
* `SwrProvider` for scoping a cache to a subtree, with a shared global cache by default.
* `mutate` for optimistic/manual cache updates, including a top-level `mutate` that reaches
  every registered `SwrCache` (not just the default).
* Conditional fetching (skip the fetch by passing a `null` key).
* `revalidateOnFocus` support via `SwrConfig`.
