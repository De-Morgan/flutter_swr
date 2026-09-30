import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_swr/flutter_swr.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

/// A paginated, pull-to-refresh view over `useSwrInfinite`: pull down to
/// refetch every loaded page, pull up to load the next one
/// (`pull_to_refresh`'s [SmartRefresher]).
///
/// [P] is the page type the fetcher returns and [I] the item type drawn;
/// [itemsOf] flattens each page into its items. Subclasses only decide how
/// the items are laid out ([buildScrollable]) — see [SwrInfiniteListView]
/// and [SwrInfiniteGridView].
///
/// Every [SmartRefresher] property is forwarded with its own default, except
/// [enablePullUp], which defaults to `true` since loading more is the point.
abstract class SwrInfiniteView<P, I> extends HookWidget {
  const SwrInfiniteView({
    super.key,
    required this.getKey,
    required this.itemsOf,
    this.fetcher,
    this.options,
    this.config,
    this.loadingBuilder,
    required this.errorBuilder,
    this.emptyBuilder,
    this.skipError = true,
    this.controller,
    this.header,
    this.footer,
    this.enablePullDown = true,
    this.enablePullUp = true,
    this.enableTwoLevel = false,
    this.onRefresh,
    this.onLoading,
    this.onTwoLevel,
    this.dragStartBehavior,
    this.primary,
    this.cacheExtent,
    this.semanticChildCount,
    this.reverse,
    this.physics,
    this.scrollDirection,
    this.scrollController,
  });

  /// Passed to `useSwrInfinite`: the key of page `pageIndex`, or `null`
  /// once [previousPage] was the last one.
  final Object? Function(int pageIndex, P? previousPage) getKey;

  /// The items of one page, in display order.
  final List<I> Function(P page) itemsOf;

  /// Loads one page from its key; falls back to `SwrConfig.fetcher`.
  final Future<P> Function(Object key)? fetcher;
  final SwrInfiniteOptions? options;
  final SwrConfig? config;

  /// Shown on first load. Defaults to a centered spinner.
  final WidgetBuilder? loadingBuilder;

  /// Shown when the first load fails and there is nothing to show; `retry`
  /// [skipError] is false, a failure once items are shown keeps them on
  /// screen instead.
  final Widget Function(
    BuildContext context,
    Object error,
    Future<void> Function() retry,
  )
  errorBuilder;

  /// Shown, still inside the refresher, when every page loaded but none has
  /// items. Defaults to a centered message.
  final WidgetBuilder? emptyBuilder;

  /// Whether a failed refresh/load-more keeps the items already on screen
  /// instead of switching to [errorBuilder]. Passed to `SwrResponse.when`.
  final bool skipError;

  /// If null, the view creates (and disposes) its own.
  final RefreshController? controller;
  final Widget? header;
  final Widget? footer;
  final bool enablePullDown;
  final bool enablePullUp;
  final bool enableTwoLevel;

  /// Called after the built-in refresh (refetching every page) completes.
  final VoidCallback? onRefresh;

  /// Called after the built-in load-more (the next page) completes.
  final VoidCallback? onLoading;
  final OnTwoLevel? onTwoLevel;
  final DragStartBehavior? dragStartBehavior;
  final bool? primary;
  final double? cacheExtent;
  final int? semanticChildCount;
  final bool? reverse;
  final ScrollPhysics? physics;
  final Axis? scrollDirection;
  final ScrollController? scrollController;

  /// The scrollable placed inside the [SmartRefresher] once there are items.
  Widget buildScrollable(BuildContext context, List<I> items);

  @override
  Widget build(BuildContext context) {
    final (pages, infinite) = useSwrInfinite<P>(
      getKey,
      fetcher: fetcher,
      options: options,
      config: config,
    );

    final ownController = useMemoized(
      () => controller == null ? RefreshController() : null,
      [controller],
    );
    useEffect(() => ownController?.dispose, [ownController]);
    final refresh = controller ?? ownController!;

    // Mark the footer as finished once there's nothing left, including when
    // the list is already complete on first load or after a refresh.
    final reachedEnd = pages.data != null && infinite.isReachingEnd;
    useEffect(() {
      reachedEnd ? refresh.loadNoData() : refresh.resetNoData();
      return null;
    }, [reachedEnd, refresh]);

    final items = [for (final page in pages.data ?? <P>[]) ...itemsOf(page)];

    // skipError (default true): a failed refresh/load-more keeps the items
    // on screen; skipLoadingOnRefresh (default) keeps SmartRefresher mounted
    // while it's refreshing/loading.
    return pages.when(
      skipError: skipError,
      loading: () =>
          loadingBuilder?.call(context) ??
          const Center(child: CircularProgressIndicator()),
      error: (error, _) => errorBuilder.call(context, error, infinite.mutate),
      data: (_) => SmartRefresher(
        controller: refresh,
        header: header,
        footer: footer,
        enablePullDown: enablePullDown,
        enablePullUp: enablePullUp,
        enableTwoLevel: enableTwoLevel,
        onRefresh: () async {
          // Refetches every loaded page (useSwrInfinite's mutate).
          await infinite.mutate();
          refresh.refreshCompleted();
          onRefresh?.call();
        },
        onLoading: () async {
          final result = await infinite.setSize(infinite.size + 1);
          if (result.error != null) {
            refresh.loadFailed();
          } else if (infinite.isReachingEnd) {
            refresh.loadNoData();
          } else {
            refresh.loadComplete();
          }
          onLoading?.call();
        },
        onTwoLevel: onTwoLevel,
        dragStartBehavior: dragStartBehavior,
        primary: primary,
        cacheExtent: cacheExtent,
        semanticChildCount: semanticChildCount,
        reverse: reverse,
        physics: physics,
        scrollDirection: scrollDirection,
        scrollController: scrollController,
        child: items.isEmpty
            ? emptyBuilder?.call(context) ??
                  const Center(child: Text('Nothing here yet'))
            : buildScrollable(context, items),
      ),
    );
  }
}

/// A [SwrInfiniteView] laid out as a list:
///
/// ```dart
/// SwrInfiniteListView<UsersPage, User>(
///   getKey: UsersApi.pageKey,
///   fetcher: usersApi.fetchPage,
///   itemsOf: (page) => page.users,
///   itemBuilder: (context, user, index) => UserTile(user: user),
/// )
/// ```
class SwrInfiniteListView<P, I> extends SwrInfiniteView<P, I> {
  const SwrInfiniteListView({
    super.key,
    required super.getKey,
    required super.itemsOf,
    required this.itemBuilder,
    this.separatorBuilder,
    this.padding,
    super.fetcher,
    super.options,
    super.config,
    super.loadingBuilder,
    required super.errorBuilder,
    super.emptyBuilder,
    super.skipError,
    super.controller,
    super.header,
    super.footer,
    super.enablePullDown,
    super.enablePullUp,
    super.enableTwoLevel,
    super.onRefresh,
    super.onLoading,
    super.onTwoLevel,
    super.dragStartBehavior,
    super.primary,
    super.cacheExtent,
    super.semanticChildCount,
    super.reverse,
    super.physics,
    super.scrollDirection,
    super.scrollController,
  });

  final Widget Function(BuildContext context, I item, int index) itemBuilder;

  /// If set, drawn between items (`ListView.separated`).
  final IndexedWidgetBuilder? separatorBuilder;
  final EdgeInsetsGeometry? padding;

  @override
  Widget buildScrollable(BuildContext context, List<I> items) {
    Widget item(BuildContext context, int index) =>
        itemBuilder(context, items[index], index);

    final separator = separatorBuilder;
    return separator == null
        ? ListView.builder(
            padding: padding,
            itemCount: items.length,
            itemBuilder: item,
          )
        : ListView.separated(
            padding: padding,
            itemCount: items.length,
            itemBuilder: item,
            separatorBuilder: separator,
          );
  }
}

/// A [SwrInfiniteView] laid out as a grid:
///
/// ```dart
/// SwrInfiniteGridView<UsersPage, User>(
///   getKey: UsersApi.pageKey,
///   fetcher: usersApi.fetchPage,
///   itemsOf: (page) => page.users,
///   gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
///     crossAxisCount: 2,
///   ),
///   itemBuilder: (context, user, index) => UserCard(user: user),
/// )
/// ```
class SwrInfiniteGridView<P, I> extends SwrInfiniteView<P, I> {
  const SwrInfiniteGridView({
    super.key,
    required super.getKey,
    required super.itemsOf,
    required this.gridDelegate,
    required this.itemBuilder,
    this.padding,
    super.fetcher,
    super.options,
    super.config,
    super.loadingBuilder,
    required super.errorBuilder,
    super.emptyBuilder,
    super.skipError,
    super.controller,
    super.header,
    super.footer,
    super.enablePullDown,
    super.enablePullUp,
    super.enableTwoLevel,
    super.onRefresh,
    super.onLoading,
    super.onTwoLevel,
    super.dragStartBehavior,
    super.primary,
    super.cacheExtent,
    super.semanticChildCount,
    super.reverse,
    super.physics,
    super.scrollDirection,
    super.scrollController,
  });

  final SliverGridDelegate gridDelegate;
  final Widget Function(BuildContext context, I item, int index) itemBuilder;
  final EdgeInsetsGeometry? padding;

  @override
  Widget buildScrollable(BuildContext context, List<I> items) {
    return GridView.builder(
      padding: padding,
      gridDelegate: gridDelegate,
      itemCount: items.length,
      itemBuilder: (context, index) =>
          itemBuilder(context, items[index], index),
    );
  }
}
