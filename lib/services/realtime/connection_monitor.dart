import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bridges OS connectivity into the realtime layer: when the network drops
/// we surface it immediately so stores can switch to polling/offline mode
/// instead of waiting for a socket timeout.
class ConnectionMonitor extends Notifier<bool> {
  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  bool build() {
    _sub ??= Connectivity()
        .onConnectivityChanged
        .listen((results) => state = !_isOffline(results));
    ref.onDispose(() => unawaited(_sub?.cancel()));
    unawaited(_probe());
    return true;
  }

  Future<void> _probe() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (ref.mounted) state = !_isOffline(results);
    } catch (_) {
      // Assume online; socket failures will still surface via transport.
    }
  }

  static bool _isOffline(List<ConnectivityResult> results) {
    if (results.isEmpty) return true;
    return results.every((r) => r == ConnectivityResult.none);
  }
}

final connectionMonitorProvider =
    NotifierProvider<ConnectionMonitor, bool>(ConnectionMonitor.new);
