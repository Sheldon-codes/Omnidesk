import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/call_experience/call_session_controller.dart';
import '../auth_session_controller.dart';
import '../fcm_service.dart';
import 'call_api.dart';
import 'call_models.dart';
import 'device_installation_service.dart';
import 'native_call_service.dart';

/// Application-level call coordinator. It owns authentication-aware device
/// registration and bridges push events into the session controller; widgets
/// remain completely unaware of FCM, installation IDs, and recovery APIs.
class CallLifecycleCoordinator {
  CallLifecycleCoordinator({
    required CallApi api,
    required DeviceRegistry registry,
    required FcmService fcm,
    required NativeCallService native,
    required CallSessionController Function() controller,
  })  : _api = api,
        _registry = registry,
        _fcm = fcm,
        _native = native,
        _controller = controller;

  final CallApi _api;
  final DeviceRegistry _registry;
  final FcmService _fcm;
  final NativeCallService _native;
  final CallSessionController Function() _controller;
  StreamSubscription<CallOffer>? _offers;
  StreamSubscription<String?>? _tokenChanges;
  StreamSubscription<NativeCallEvent>? _nativeEvents;
  String? _workspaceId;
  bool _active = false;
  bool _recovering = false;

  Future<void> start(AuthState auth) async {
    if (!auth.isAuthenticated || _active) return;
    _active = true;
    _workspaceId = auth.session?.user.activeWorkspace?.id;
    developer.log(
      'Call lifecycle started workspace=${_workspaceId ?? "none"}.',
      name: 'CallLifecycle',
    );
    _offers = _fcm.incomingCallOffers.listen(_onOffer);
    _nativeEvents = _native.events.listen(_onNativeEvent);
    _tokenChanges = _fcm.tokenChanges.listen((_) {
      unawaited(_register());
    });
    await _register();
    await _drainNativeOffer();
    final action = await _native.takePendingAction();
    if (action?.type == NativeCallEventType.answer) {
      await _controller().answer();
    } else if (action?.type == NativeCallEventType.decline) {
      await _controller().decline();
    }
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
    } catch (error) {
      // Registration failure is recoverable: FCM token refresh/resume will
      // retry. It must not sign the agent out or block normal app navigation.
      developer.log(
        'Push-device registration will retry: ${error.runtimeType}.',
        name: 'PushRegistration',
      );
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
    developer.log(
      'Incoming offer received in Flutter callId=${offer.callId} '
      'offerId=${offer.offerId} workspace=${offer.workspaceId} '
      'expired=${offer.isExpired}.',
      name: 'CallLifecycle',
    );
    if (!_active || offer.isExpired) {
      developer.log(
        'Incoming offer ignored: active=$_active expired=${offer.isExpired}.',
        name: 'CallLifecycle',
      );
      return;
    }
    // An offer belongs to one workspace. Never surface stale/background data
    // for a workspace the agent has switched away from.
    if (_workspaceId != null &&
        _workspaceId!.isNotEmpty &&
        offer.workspaceId != _workspaceId) {
      developer.log(
        'Incoming offer ignored: workspace mismatch.',
        name: 'CallLifecycle',
      );
      return;
    }
    final handled = await _controller().handleIncomingOffer(offer);
    developer.log(
      'Incoming offer handed to session controller handled=$handled.',
      name: 'CallLifecycle',
    );
  }

  Future<void> _onNativeEvent(NativeCallEvent event) async {
    developer.log(
      'Native call event type=${event.type.name} callId=${event.callId ?? "none"} '
      'callSid=${event.callSid ?? "none"} mediaSession=${event.mediaSessionId ?? "none"} '
      'reason=${event.reason ?? "none"}.',
      name: 'CallLifecycle',
    );
    switch (event.type) {
      case NativeCallEventType.offerAvailable:
        await _drainNativeOffer();
      case NativeCallEventType.nativePushTokenChanged:
        await _register();
      case NativeCallEventType.answer:
      case NativeCallEventType.decline:
      case NativeCallEventType.end:
      case NativeCallEventType.incomingPresented:
      case NativeCallEventType.outgoingDialing:
      case NativeCallEventType.active:
      case NativeCallEventType.disconnected:
      case NativeCallEventType.failed:
        break;
    }
  }

  Future<void> _drainNativeOffer() async {
    developer.log('Draining pending native incoming offer.',
        name: 'CallLifecycle');
    final offer = await _native.takePendingOffer();
    developer.log(
      'Pending native offer ${offer == null ? "not found" : "found callId=${offer.callId}"}.',
      name: 'CallLifecycle',
    );
    if (offer != null) await _onOffer(offer);
  }

  Future<void> stop() async {
    _active = false;
    _workspaceId = null;
    await _offers?.cancel();
    await _tokenChanges?.cancel();
    await _nativeEvents?.cancel();
    _offers = null;
    _tokenChanges = null;
    _nativeEvents = null;
  }

  Future<void> dispose() => stop();
}

final callLifecycleCoordinatorProvider =
    Provider<CallLifecycleCoordinator>((ref) {
  final coordinator = CallLifecycleCoordinator(
    api: ref.read(callApiProvider),
    registry: ref.read(deviceRegistryProvider),
    fcm: ref.read(fcmServiceProvider),
    native: ref.read(nativeCallServiceProvider),
    controller: () => ref.read(callSessionControllerProvider.notifier),
  );
  ref.onDispose(() => unawaited(coordinator.dispose()));
  return coordinator;
});
