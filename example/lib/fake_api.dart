/// A fake in-memory "backend" for the example app, so it runs offline (and
/// in CI) with no real network dependency. Every method tracks how many
/// times it's actually been called, so the UI can prove dedup is working —
/// two widgets sharing a key should still only bump these counts by one.
class FakeApi {
  int profileFetchCount = 0;
  int sharedCounterFetchCount = 0;
  int sessionFetchCount = 0;

  Future<Profile> fetchProfile(String userId) async {
    profileFetchCount++;
    await Future.delayed(const Duration(seconds: 1));
    return Profile(
      userId: userId,
      name: 'User $userId',
      fetchedAt: DateTime.now(),
    );
  }

  /// A counter that increments server-side on every *real* fetch — shared
  /// by two widgets in the demo to make deduplication visible: if it only
  /// goes up by one while both widgets are mounted together, only one
  /// fetch actually happened.
  Future<int> fetchSharedCounter() async {
    sharedCounterFetchCount++;
    await Future.delayed(const Duration(milliseconds: 800));
    return sharedCounterFetchCount;
  }

  /// Returns a session with a `userId` when [loggedIn], or `null` when not
  /// — the profile-dependent-fetching demo uses this to gate a second
  /// `useSwr` call on the result of a first one.
  Future<Session?> fetchSession({required bool loggedIn}) async {
    sessionFetchCount++;
    await Future.delayed(const Duration(milliseconds: 600));
    return loggedIn ? Session(userId: 'depends-on-session') : null;
  }
}

class Profile {
  const Profile({required this.userId, required this.name, required this.fetchedAt});

  final String userId;
  final String name;
  final DateTime fetchedAt;
}

class Session {
  const Session({required this.userId});

  final String userId;
}
