import 'package:flutter_swr/flutter_swr.dart';
import 'package:observe_internet_connectivity/observe_internet_connectivity.dart';

/// Plugs `observe_internet_connectivity` into flutter_swr, so every mounted
/// key revalidates when the device regains internet access
/// (`SwrConfig.revalidateOnReconnect`).
///
/// flutter_swr doesn't depend on any connectivity package — any source of
/// online/offline status works. With `connectivity_plus` instead:
///
/// ```dart
/// class ConnectivityPlusAdapter extends SwrConnectivity {
///   @override
///   Stream<bool> get onConnectivityChanged => Connectivity()
///       .onConnectivityChanged
///       .map((results) => !results.contains(ConnectivityResult.none));
/// }
/// ```
///
/// (`connectivity_plus` only reports the network interface, not whether the
/// internet is actually reachable; `observe_internet_connectivity` checks
/// reachability, which is why the example uses it.)
class InternetConnectivityAdapter extends SwrConnectivity {
  InternetConnectivityAdapter([InternetConnectivity? source])
    : _source = source ?? InternetConnectivity();

  final InternetConnectivity _source;

  @override
  Stream<bool> get onConnectivityChanged => _source.observeInternetConnection;
}
