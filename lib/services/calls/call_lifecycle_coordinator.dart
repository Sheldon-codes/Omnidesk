import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/call_experience/call_session_controller.dart';
import '../auth_session_controller.dart';
import '../fcm_service.dart';
import 'call_api.dart';
import 'call_models.dart';
import 'device_installation_service.dart';

/// Application-level call coordinator. It owns authentication-aware device
/// registration and bridges push events into the session controller; widgets
/// remain completely unaware of FCM, installation IDs, and recovery APIs.
class CallLifecycleCoordinator {
  CallLifecycleCoordinator({
    required CallApi api,
    required DeviceRegistry registry,
    required FcmService fcm,
    required CallSessionController Function() controller,
  })  : _api = api,
        _registry = registry,
        _fcm = fcm,
        _controller = controller;

  final CallApi _api;
  final DeviceRegistry _registry;
  final FcmService _fcm;
  final CallSessionController Function() _controller;
  StreamSubscription<CallOffer>? _offers;
  StreamSubscription<String?>? _tokenChanges;
  String? _workspaceId;
  bool _active = false;
  bool _recovering = false;

  Future<void> start(AuthState auth) async {
    if (!auth.isAuthenticated || _active) return;
    _active = true;
    _workspaceId = auth.session?.user.activeWorkspace?.id;
    _offers = _fcm.incomingCallOffers.listen(_onOffer);
    _tokenChanges = _fcm.tokenChanges.listen((_) {
      unawaited(_register());
    });
    await _register();
    await recover();
  }

  Future<void> updateAuth(AuthState auth) async {
    if (!auth.isAuthenticated) {
      await stop();
      return;
    }
    final newWorkspace = auth.session?.user.activeWorkspace?.id;
    if (!_active) {
      await start(auth);
      return;
    }
    if (newWorkspace != _workspaceId) {
      _workspaceId = newWorkspace;
      _registry.invalidateRegistration();
      await _register();
      await recover();
    }
  }

  Future<void> _register() async {
    if (!_active) return;
    try {
      await _registry.register();
    } catch (_) {
      // Registration failure is recoverable: FCM token refresh/resume will
      // retry. It must not sign the agent out or block normal app navigation.
    }
  }

  Future<void> recover() async {
    if (!_active || _recovering) return;
    _recovering = true;
    try {
      final snapshot = await _api.getActiveCall();
      await _controller().recover(snapshot);
    } on CallApiException {
      // Recovery is best-effort; the next foreground lifecycle retries.
    } finally {
      _recovering = false;
    }
  }

  Future<void> _onOffer(CallOffer offer) async {
    if (!_active || offer.isExpired) return;
    // An offer belongs to one workspace. Never surface stale/background data
    // for a workspace the agent has switched away from.
    if (_workspaceId != null &&
        _workspaceId!.isNotEmpty &&
        offer.workspaceId != _workspaceId) {
      return;
    }
    await _controller().handleIncomingOffer(offer);
  }

  Future<void> stop() async {
    _active = false;
    _workspaceId = null;
    await _offers?.cancel();
    await _tokenChanges?.cancel();
    _offers = null;
    _tokenChanges = null;
  }

  Future<void> dispose() => stop();
}

final callLifecycleCoordinatorProvider =
    Provider<CallLifecycleCoordinator>((ref) {
  final coordinator = CallLifecycleCoordinator(
    api: ref.read(callApiProvider),
    registry: ref.read(deviceRegistryProvider),
    fcm: ref.read(fcmServiceProvider),
    controller: () => ref.read(callSessionControllerProvider.notifier),
  );
  ref.onDispose(() => unawaited(coordinator.dispose()));
  return coordinator;
});
