import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/pages/conversation_room_page/whatsapp_live_store.dart';
import 'package:omnidesk_agent/services/api_service.dart';

class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.body);
  final String body;
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    request = options;
    return ResponseBody.fromString(body, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('compose sends through workspace service with CRM customer and message',
      () async {
    final adapter = _JsonAdapter('''
      {"success":true,"ticket_id":42,"message_id":"wamid.1",
      "created_ticket":true,"customer":{"id":88,"name":"David"},
      "entry":{"id":510,"event_type":"agent_reply"}}
    ''');
    final api = ApiService(
      baseUrl: 'https://api.example.test',
      dio: Dio(BaseOptions(baseUrl: 'https://api.example.test'))
        ..httpClientAdapter = adapter,
      readAccessToken: () => 'token',
      readWorkspaceId: () => '6',
      onUnauthorized: () async {},
    );

    final ticketId = await WhatsAppRepository(api).compose(
      customerId: '88',
      phone: '+254712345678',
      name: 'David Mwangi',
      message: '  Hello from the workspace  ',
    );

    expect(ticketId, 42);
    expect(adapter.request?.method, 'POST');
    expect(adapter.request?.path, '/whatsapp/compose');
    expect(adapter.request?.data, {
      'customer_id': 88,
      'name': 'David Mwangi',
      'message': 'Hello from the workspace',
    });
    expect(adapter.request?.headers['X-Workspace-Id'], '6');
    expect(adapter.request?.headers['Authorization'], 'Bearer token');
  });

  test('compose rejects empty message before sending', () async {
    final adapter = _JsonAdapter('{}');
    final api = ApiService(
      baseUrl: 'https://api.example.test',
      dio: Dio(BaseOptions(baseUrl: 'https://api.example.test'))
        ..httpClientAdapter = adapter,
      readAccessToken: () => null,
      readWorkspaceId: () => null,
      onUnauthorized: () async {},
    );
    await expectLater(
      WhatsAppRepository(api).compose(customerId: '88', message: '  '),
      throwsA(isA<ApiClientException>()),
    );
    expect(adapter.request, isNull);
  });
}
