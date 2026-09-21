import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/services/api_service.dart';
import 'package:omnidesk_agent/services/calls/call_api.dart';
import 'package:omnidesk_agent/services/calls/call_models.dart';

class _CallAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final body = switch (options.path) {
      '/calls/media-config' => {
          'success': true,
          'provider': 'africas_talking',
          'transport': 'sip',
          'endpoint_type': 'mobile',
          'sip': {
            'uri': 'sip:agent@sip.example.test',
            'username': 'agent',
            'auth_username': 'agent-auth',
            'password': 'ephemeral-secret',
            'registrar': 'sip.example.test',
            'domain': 'sip.example.test',
            'proxy': 'sip.example.test:5061',
            'transport': 'tls',
            'port': 5061,
          },
          'capabilities': {'hold': true, 'dtmf': true, 'native_incoming': true},
        },
      '/calls/active' => {
          'active': true,
          'call': {
            'call_id': 'call-1',
            'direction': 'inbound',
            'status': 'in_progress',
            'caller_number': '+254700000001',
            'customer_name': 'Aloise',
            'created_at': '2026-09-09T10:00:00Z',
            'answered_at': '2026-09-09T10:00:05Z',
          },
        },
      '/calls/logs' => {
          'data': [
            {
              'call_id': 'call-log-1',
              'call_sid': 'AT-call-sess-9921',
              'direction': 'inbound',
              'status': 'completed',
              'from_number': '+254700000002',
              'to_number': '0743379990',
              'customer_phone': '+254700000002',
              'customer_name': 'Jane Doe',
              'customer': {
                'id': 89,
                'name': 'Jane Doe',
                'phone_number': '+254700000002',
                'email': 'jane.doe@example.test',
              },
              'duration': 83,
              'formatted_duration': '1:23',
              'ticket': {
                'id': 42,
                'display_number': '#TKT-42',
                'subject': 'Billing issue',
              },
              'recording_url': 'https://recordings.example.test/call-log-1',
              'created_at': '2026-09-09T10:02:00Z',
            },
          ],
          'meta': {'current_page': 1, 'last_page': 2},
        },
      '/calls/initiate' => {
          'success': true,
          'call_sid': 'AT-call-sess-initiated',
        },
      '/calls/call-1/accept' => {
          'call_id': 'call-1',
          'status': 'in_progress',
          'caller_number': '+254700000001',
          'connected_at': '2026-09-09T10:00:05Z',
        },
      _ => {'success': true},
    };
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
      'remote call API sends documented device and incoming lifecycle payloads',
      () async {
    final adapter = _CallAdapter();
    final api = ApiService(
      baseUrl: 'https://api.example.test/api/v1',
      dio: Dio()..httpClientAdapter = adapter,
      readAccessToken: () => 'access-token',
      readWorkspaceId: () => 'workspace-7',
      onUnauthorized: () async {},
    );
    final calls = RemoteCallApi(api);

    await calls.registerDevice(const DeviceRegistration(
      installationId: 'f2ad9694-2c28-4c09-95bd-6cc44dbf5d07',
      platform: 'android',
      appVersion: '1.0.0+1',
      deviceName: 'Pixel',
      voipCapable: true,
      fcmToken: 'fcm-token',
    ));
    expect(adapter.requests.single.path, '/agent/devices');
    expect(
        adapter.requests.single.data,
        containsPair(
            'installation_id', 'f2ad9694-2c28-4c09-95bd-6cc44dbf5d07'));
    expect(adapter.requests.single.headers['Authorization'],
        'Bearer access-token');
    expect(adapter.requests.single.headers['X-Workspace-Id'], 'workspace-7');

    await calls.acknowledgeDelivery(
      callId: 'call-1',
      offerId: 'offer-1',
      installationId: 'install-1',
      receivedAt: DateTime.utc(2026, 9, 19, 15, 25, 41, 184),
      nativePresentedAt: DateTime.utc(2026, 9, 19, 15, 25, 41, 390),
    );
    expect(adapter.requests.last.data, {
      'offer_id': 'offer-1',
      'installation_id': 'install-1',
      'received_at': '2026-09-19T15:25:41.184Z',
      'native_presented_at': '2026-09-19T15:25:41.390Z',
    });
    await calls.accept(
        callId: 'call-1', offerId: 'offer-1', installationId: 'install-1');
    await calls.mediaReady(
        callId: 'call-1', offerId: 'offer-1', installationId: 'install-1');
    await calls.decline(
      callId: 'call-1',
      offerId: 'offer-1',
      installationId: 'install-1',
      reason: 'agent_declined',
    );
    await calls.end(callId: 'call-1', reason: 'agent_hangup');
    await calls.completeOutbound(
      callSid: 'AT-call-sess-initiated',
      connectedDuration: const Duration(seconds: 18),
    );
    final outbound = await calls.initiateOutbound(
      toNumber: '+254712345678',
      ticketId: '14',
    );

    expect(
        adapter.requests.map((request) => request.path),
        containsAll([
          '/calls/call-1/delivery-ack',
          '/calls/call-1/accept',
          '/calls/call-1/media-ready',
          '/calls/call-1/decline',
          '/calls/call-1/end',
          '/calls/complete',
          '/calls/initiate',
        ]));
    expect(adapter.requests[2].data,
        {'installation_id': 'install-1', 'offer_id': 'offer-1'});
    expect(outbound.callSid, 'AT-call-sess-initiated');
    expect(adapter.requests.last.data,
        {'to_number': '+254712345678', 'ticket_id': 14});
    expect(adapter.requests[6].data,
        {'call_sid': 'AT-call-sess-initiated', 'duration': 18});
  });

  test('media config and active recovery retain server call identity',
      () async {
    final adapter = _CallAdapter();
    final calls = RemoteCallApi(ApiService(
      baseUrl: 'https://api.example.test/api/v1',
      dio: Dio()..httpClientAdapter = adapter,
      readAccessToken: () => 'token',
      onUnauthorized: () async {},
    ));

    final config = await calls.getMediaConfig();
    expect(config.canAuthenticate, isTrue);
    expect(config.port, 5061);
    expect(config.sipAuthUsername, 'agent-auth');
    expect(config.sipProxy, 'sip.example.test:5061');
    final active = await calls.getActiveCall();
    expect(active?.callId, 'call-1');
    expect(active?.customerName, 'Aloise');
  });

  test('call logs use the live paginated endpoint and map recording metadata',
      () async {
    final adapter = _CallAdapter();
    final calls = RemoteCallApi(ApiService(
      baseUrl: 'https://api.example.test/api/v1',
      dio: Dio()..httpClientAdapter = adapter,
      readAccessToken: () => 'token',
      readWorkspaceId: () => 'workspace-7',
      onUnauthorized: () async {},
    ));

    final page = await calls.getCallLogs(page: 1, perPage: 20);

    expect(adapter.requests.single.path, '/calls/logs');
    expect(
        adapter.requests.single.queryParameters, {'page': 1, 'per_page': 20});
    expect(adapter.requests.single.headers['X-Workspace-Id'], 'workspace-7');
    expect(page.hasMore, isTrue);
    expect(page.records.single.customerName, 'Jane Doe');
    expect(page.records.single.phoneNumber, '+254700000002');
    expect(page.records.single.duration, const Duration(seconds: 83));
    expect(page.records.single.formattedDuration, '1:23');
    expect(page.records.single.ticketNumber, '#TKT-42');
    expect(page.records.single.ticketSubject, 'Billing issue');
    expect(page.records.single.recordingUrl,
        'https://recordings.example.test/call-log-1');
  });

  test('call log mapper uses the resolved customer phone for outbound calls',
      () {
    final record = CallLogRecord.fromJson({
      'id': 12,
      'direction': 'outbound',
      'status': 'completed',
      'from_number': '+254709369917',
      'to_number': '0743379990',
      'customer_phone': '+254712345678',
      'customer_name': 'Jane Doe',
      'duration': 142,
      'formatted_duration': '2:22',
      'ticket': {'display_number': '#TKT-14', 'subject': 'Billing issue'},
      'created_at': '2026-09-04T16:25:00+03:00',
    });

    expect(record.customerName, 'Jane Doe');
    expect(record.phoneNumber, '+254712345678');
    expect(record.ticketNumber, '#TKT-14');
    expect(record.duration, const Duration(seconds: 142));
  });
}
