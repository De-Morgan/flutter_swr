import 'package:flutter/widgets.dart';

import 'swr_config.dart';

/// Scopes an [SwrConfig] to a widget subtree.
///
/// Nested providers merge: this provider's [config] is merged on top of
/// the nearest ancestor [SwrProvider]'s resolved config (this provider's
/// non-null fields win; unset fields fall through to the ancestor's). A
/// root provider — one with no ancestor [SwrProvider] — has its unset
/// fields filled from [SwrConfig.defaults] instead, so [SwrProvider.of]
/// never has to null-check its way to a usable config.
class SwrProvider extends StatelessWidget {
  const SwrProvider({super.key, required this.config, required this.child});

  final SwrConfig config;
  final Widget child;

  /// The resolved (fully merged, defaults-filled) config for [context].
  /// Falls back to [SwrConfig.defaults] when no [SwrProvider] is present
  /// in the tree, so `useSwr` works with zero setup.
  static SwrConfig of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_SwrConfigScope>();
    return scope?.config ?? SwrConfig.defaults;
  }

  @override
  Widget build(BuildContext context) {
    final ancestor = context
        .getInheritedWidgetOfExactType<_SwrConfigScope>()
        ?.config;
    final merged = ancestor == null ? config.withDefaults() : ancestor.merge(config);
    return _SwrConfigScope(config: merged, child: child);
  }
}

class _SwrConfigScope extends InheritedWidget {
  const _SwrConfigScope({required this.config, required super.child});

  final SwrConfig config;

  @override
  bool updateShouldNotify(_SwrConfigScope oldWidget) => true;
}
