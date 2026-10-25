import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Calls [revalidate] each time the calling widget becomes visible again
/// after being hidden, while [enabled] — see `SwrConfig.revalidateOnFocus`.
///
/// The widget counts as visible when both [Visibility.of] (which
/// [IndexedStack] and [Visibility] set false for hidden children) and the
/// ambient [TickerMode] (which [Overlay] turns off for routes covered by an
/// opaque route, as do go_router's shell branches) say so. Both are only
/// depended on while [enabled], so widgets that don't opt in never rebuild
/// on visibility changes.
void useRevalidateOnFocus({
  required bool enabled,
  required void Function() revalidate,
}) {
  final context = useContext();
  final isVisible =
      !enabled ||
      (Visibility.of(context) && TickerMode.valuesOf(context).enabled);
  final wasVisible = useRef(isVisible);
  useEffect(() {
    final regainedFocus = isVisible && !wasVisible.value;
    wasVisible.value = isVisible;
    if (regainedFocus) revalidate();
    return null;
  }, [isVisible]);
}
