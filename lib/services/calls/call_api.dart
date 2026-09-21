import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api_service.dart';
import 'call_models.dart';

enum CallApiErrorKind {
  authentication,
  offerExpired,
  alreadyClaimed,
  unavailable,
  validation,
  network,
  malformed,
  server,
}

class CallApiException implements Exception {
  const CallApiException(this.kind, this.message, {this.statusCode});
  final CallApiErrorKind kind;
  final String message;
  final int? statusCode;

  factory CallApiException.fromApi(ApiClientException error) {
    final code = error.code?.toUpperCase();
    final message = error.message;
    if (error.statusCode == 401 || error.statusCode == 403) {
      return CallApiException(
        CallApiErrorKind.authentication,
        'Your session has expired. Please sign in again.',
        statusCode: error.statusCode,
      );
    }
    if (error.statusCode == 409 &&
        (code == 'CALL_ALREADY_CLAIMED' ||
            message.contains('already claimed'))) {
      return CallApiException(
        CallApiErrorKind.alreadyClaimed,
        'This call was answered on another device.',
        statusCode: error.statusCode,
      );
    }
    if (error.statusCode == 410 || code == 'CALL_OFFER_EXPIRED') {
      return CallApiException(
        CallApiErrorKind.offerExpired,
        'This call offer has expired.',
        statusCode: error.statusCode,
      );
    }
    if (error.isNetworkError) {
      return CallApiException(CallApiErrorKind.network,
          'Unable to reach the call service. Check your connection.');
    }
    if (error.statusCode == 422) {
      return CallApiException(CallApiErrorKind.validation, message,
          statusCode: error.statusCode);
    }
    return CallApiException(CallApiErrorKind.server, message,
        statusCode: error.statusCode);
  }
}

class DeviceRegistration {
  const DeviceRegistration({
    required this.installationId,
    required this.platform,
    required this.appVersion,
    required this.deviceName,
    required this.voipCapable,
    this.fcmToken,
    this.apnsToken,
    this.voipPushToken,
  });

  final String installationId;
  final String platform;
  final String appVersion;
  final String deviceName;
  final bool voipCapable;
  final String? fcmToken;
  final String? apnsToken;
  final String? voipPushToken;

  Map<String, dynamic> toJson() => {
        'installation_id': installationId,
        'platform': platform,
        'app_version': appVersion,
        'device_name': deviceName,
        'voip_capable': voipCapable,
        if (fcmToken != null && fcmToken!.isNotEmpty) 'fcm_token': fcmToken,
        if (apnsToken != null && apnsToken!.isNotEmpty) 'apns_token': apnsToken,
        if (voipPushToken != null && voipPushToken!.isNotEmpty)
          'voip_push_token': voipPushToken,
      };
}

abstract class CallApi {
  Future<void> registerDevice(DeviceRegistration registration);
  Future<void> unregisterDevice(String installationId);
  Future<CallMediaConfig> getMediaConfig();
  Future<void> acknowledgeDelivery({
    required CallId callId,
    required CallOfferId offerId,
    required String installationId,
    required DateTime receivedAt,
    required DateTime nativePresentedAt,
  });
  Future<ActiveCallSnapshot> accept({
    required CallId callId,
    required CallOfferId offerId,
    required String installationId,
  });
  Future<void> mediaReady({
    required CallId callId,
    required CallOfferId offerId,
    required String installationId,
  });
  Future<void> decline({
    required CallId callId,
    required CallOfferId offerId,
    required String installationId,
    required String reason,
  });
  Future<void> end({required CallId callId, required String reason});
  Future<void> completeOutbound({
    required String callSid,
    required Duration connectedDuration,
  });
  Future<OutboundCallResult> initiateOutbound({
    required String toNumber,
    String? ticketId,
  });
  Future<ActiveCallSnapshot?> getActiveCall();
  Future<CallLogPage> getCallLogs({int page = 1, int perPage = 20});
}

class RemoteCallApi implements CallApi {
  const RemoteCallApi(this._api);
  final ApiService _api;

  @override
  Future<void> registerDevice(DeviceRegistration registration) async {
    await _post('/agent/devices', registration.toJson());
  }

  @override
  Future<void> unregisterDevice(String installationId) =>
      _delete('/agent/devices/$installationId');

  @override
  Future<CallMediaConfig> getMediaConfig() async {
    final map = await _getMap('/calls/media-config');
    return CallMediaConfig.fromJson(map);
  }

  @override
  Future<void> acknowledgeDelivery({
    required CallId callId,
    required CallOfferId offerId,
    required String installationId,
    required DateTime receivedAt,
    required DateTime nativePresentedAt,
  }) =>
      _post('/calls/$callId/delivery-ack', {
        'offer_id': offerId,
        'installation_id': installationId,
        'received_at': receivedAt.toUtc().toIso8601String(),
        'native_presented_at': nativePresentedAt.toUtc().toIso8601String(),
      });

  @override
  Future<ActiveCallSnapshot> accept({
    required CallId callId,
    required CallOfferId offerId,
    required String installationId,
  }) async {
    final map = await _post('/calls/$callId/accept', {
      'installation_id': installationId,
      'offer_id': offerId,
    });
    return ActiveCallSnapshot.fromJson(map);
  }

  @override
  Future<void> mediaReady({
    required CallId callId,
    required CallOfferId offerId,
    required String installationId,
  }) =>
      _post('/calls/$callId/media-ready', {
        'installation_id': installationId,
        'offer_id': offerId,
        'transport': 'webrtc',
      });

  @override
  Future<void> decline({
    required CallId callId,
    required CallOfferId offerId,
    required String installationId,
    required String reason,
  }) =>
      _post('/calls/$callId/decline', {
        'installation_id': installationId,
        'offer_id': offerId,
        'reason': reason,
      });

  @override
  Future<void> end({required CallId callId, required String reason}) =>
      _post('/calls/$callId/end', {'reason': reason});

  @override
  Future<void> completeOutbound({
    required String callSid,
    required Duration connectedDuration,
  }) =>
      _post('/calls/complete', {
        'call_sid': callSid,
        'duration': connectedDuration.inSeconds,
      });

  @override
  Future<OutboundCallResult> initiateOutbound({
    required String toNumber,
    String? ticketId,
  }) async {
    final normalizedNumber = toNumber.trim();
    if (normalizedNumber.isEmpty) {
      throw const CallApiException(
        CallApiErrorKind.validation,
        'Enter a phone number before starting a call.',
      );
    }
    final parsedTicketId = int.tryParse(ticketId?.trim() ?? '');
    final response = await _post('/calls/initiate', {
      'to_number': normalizedNumber,
      if (parsedTicketId != null) 'ticket_id': parsedTicketId,
    });
    if (response['success'] != true) {
      throw const CallApiException(
        CallApiErrorKind.server,
        'The call service did not accept the outbound call.',
      );
    }
    try {
      return OutboundCallResult.fromJson(response);
    } on FormatException catch (error) {
      throw CallApiException(CallApiErrorKind.malformed, error.message);
    }
  }

  @override
  Future<ActiveCallSnapshot?> getActiveCall() async {
    final map = await _getMap('/calls/active');
    if (map['active'] != true || map['call'] is! Map) return null;
    return ActiveCallSnapshot.fromJson(
      (map['call'] as Map).map((key, value) => MapEntry('$key', value)),
    );
  }

  @override
  Future<CallLogPage> getCallLogs({int page = 1, int perPage = 20}) async {
    try {
      final response = await _api.get(
        '/calls/logs',
        queryParameters: {'page': page, 'per_page': perPage},
      );
      return CallLogPage.fromJson(response, requestedPage: page);
    } on ApiClientException catch (error) {
      throw CallApiException.fromApi(error);
    }
  }

  Future<Map<String, dynamic>> _getMap(String path) async {
    try {
      final response = await _api.get(path);
      return _map(response);
    } on ApiClientException catch (error) {
      throw CallApiException.fromApi(error);
    }
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    try {
      final response = await _api.post(path, body);
      return _map(response);
    } on ApiClientException catch (error) {
      throw CallApiException.fromApi(error);
    }
  }

  Future<void> _delete(String path) async {
    try {
      await _api.delete(path);
    } on ApiClientException catch (error) {
      throw CallApiException.fromApi(error);
    }
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is! Map) {
      throw const CallApiException(
        CallApiErrorKind.malformed,
        'The call service returned an invalid response.',
      );
    }
    return value.map((key, nested) => MapEntry('$key', nested));
  }
}

final callApiProvider =
    Provider<CallApi>((ref) => RemoteCallApi(ref.read(apiServiceProvider)));
