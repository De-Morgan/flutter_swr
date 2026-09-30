import 'package:flutter/material.dart';
import 'package:flutter_swr/flutter_swr.dart';

import '../../widgets/retry_error.dart';
import '../../widgets/swr_infinite_view.dart';
import 'users_api.dart';

/// `useSwrInfinite` demo: a paginated user list from reqres.in, with
/// pull-down to refresh and pull-up to load the next page
/// (see [SwrInfiniteListView]).
///
/// Scoped to its own in-memory cache, so it doesn't need a codec in the
/// app's persisted store cache.
class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SwrProvider(
      config: SwrConfig(cache: _usersCache),
      child: const _UsersView(),
    );
  }
}

/// Created once, not per build: a cache (and the controller registry the
/// package keeps per cache instance) must outlive the screen for loaded
/// pages and `size` to survive leaving and reopening it.
final SwrCache _usersCache = InMemoryCache();

class _UsersView extends StatelessWidget {
  const _UsersView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      body: SwrInfiniteListView<UsersPage, User>(
        getKey: UsersApi.pageKey,
        fetcher: usersApi.fetchPage,
        itemsOf: (page) => page.users,
        itemBuilder: (context, user, _) => _UserTile(user: user),
        errorBuilder: (context, error, mutate) =>
            RetryErrorView(message: '$error', onRetry: mutate),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(backgroundImage: NetworkImage(user.avatar)),
      title: Text(user.name),
      subtitle: Text(user.email),
      trailing: Text('#${user.id}'),
    );
  }
}
