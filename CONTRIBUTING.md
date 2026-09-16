# Contributing to flutter_swr

Thanks for your interest in improving `flutter_swr` — a stale-while-revalidate
data-fetching library for Flutter, built on `flutter_hooks`. This document
covers how the package is organized, how to work on it locally, and where to
find the highest-value work.

## Before you start

- [PRODUCT_DETAILS.md](PRODUCT_DETAILS.md) is the source of truth for _why_
  the package is shaped the way it is — API rationale, scope boundaries, and
  open questions.

If a change you're planning would alter the product rationale, update
PRODUCT_DETAILS.md as part of your PR rather than letting it drift out of
sync with the code.

## Project layout

```
lib/
  flutter_swr.dart        # public export barrel — add new public API here
  src/
    cache/                # SwrCache interface, InMemoryCache, key normalization
    core/                 # dedup manager, retry policy, scheduler, SwrController
    mutation/              # bound + global mutate
    config/                # SwrConfig, SwrProvider
    hooks/                 # useSwr, SwrResponse
    lifecycle/              # app-lifecycle-driven revalidation
test/                       # mirrors lib/src/ 1:1 — every file has a matching test file
example/                    # runnable demo app (fake in-memory API, no network)
```

Anything under `lib/src/` is internal; only export new public surface through
`lib/flutter_swr.dart`.

## Local setup

```sh
flutter pub get
```

## Running tests

```sh
flutter test                 # full suite
flutter test test/core/      # a single directory
flutter test test/core/swr_controller_test.dart   # a single file
```

Guidelines the existing suite follows and new tests should too:

- **No real network or real delays.** Fetchers are fakes you control; timing
  (retry backoff, polling intervals, dedup windows) is driven by injected
  clocks or the `fake_async` package, never `Future.delayed` in real time.
- **Pure-Dart modules stay pure-Dart.** Code under `cache/`, `core/`, and
  `mutation/` must not import `flutter` or `flutter_hooks` — keep it testable
  under plain `test`, not just `flutter_test`.
- **Widget/hook-facing code** (`hooks/`, `config/`, `lifecycle/`) is tested
  with `flutter_test`, using `HookBuilder` or the example app's fake API where
  a real widget tree is needed.

## Static analysis

```sh
flutter analyze
```

The package uses `flutter_lints`; a change isn't ready for review until this
is clean.

## Example app

The example app (`example/`) is a working demo, not a toy — it backs several
of the MVP acceptance criteria (dedup, stale-while-revalidate, app-resume
revalidation). If your change affects hook behavior, run it and exercise the
change manually before opening a PR:

```sh
cd example
flutter run
```

## Making a change

1. Open an issue or check existing ones before starting non-trivial work, so
   effort isn't duplicated.
2. Follow the module boundaries in [Project layout](#project-layout) above —
   if your change spills well outside the module it touches, that's worth
   flagging in the PR description.
3. Add or update tests in the mirrored `test/` path alongside any `lib/`
   change. A PR without test coverage for new behavior will be asked to add
   it.
4. Keep `flutter analyze` and `flutter test` clean.
5. Update [PRODUCT_DETAILS.md](PRODUCT_DETAILS.md) if the change affects the
   public API or rationale it describes.

## What's left — Post-MVP work

The MVP is complete: caching, dedup, retry, `useSwr`, bound and global
`mutate`, app-lifecycle revalidation, polling, and conditional fetching are
all implemented and tested, and the example app demonstrates every MVP
pattern. The following Post-MVP features are open and are the best place to
contribute right now:

- **Reconnect adapter** — a `connectivity_plus`-backed adapter, shipped as a
  separate package or an optional import, that revalidates mounted keys on
  an offline→online transition by reusing the same throttled revalidation
  path as app-resume. Must add zero new dependencies to the core package.
- **Pluggable/persisted cache providers** — mostly a validation effort:
  implement a reference non-default `SwrCache` (e.g. a simple persisted
  cache in `/example` or a docs snippet) to confirm the `SwrCache` interface
  needs no changes to support one. If it _does_ need changes, that's the
  finding this work exists to surface.
- **`useSwrInfinite`** — paginated fetching via
  `getKey(pageIndex, previousPageData)`, `size`/`setSize`, a sequential
  default with an opt-in `parallel: true` mode, and `revalidateFirstPage`/
  `persistSize` options. Each page reuses `SwrController` unchanged; the hook
  layer composes them into one aggregate `SwrResponse<List<T>>`.

## Commit / PR conventions

- Keep PRs scoped to one feature or one logical change where possible.
- Update `CHANGELOG.md` for any change to public API behavior.
