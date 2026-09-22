import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/pages/customers_page/customer_repository.dart';
import 'package:omnidesk_agent/services/api_service.dart';

class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.body);
  final String body;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(body, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('list sends documented pagination/search and maps summary fields',
      () async {
    final adapter = _JsonAdapter('''
      {"data":[{"id":88,"name":"David Mwangi","phone_number":"+254768270973",
      "email":"david@example.com","company":"Nairobi Tech Ltd","tickets_count":4,
      "created_at":"2026-07-15T08:00:00Z"}],
      "meta":{"current_page":2,"last_page":4,"per_page":20,"total":71}}
    ''');
    final api = _api(adapter);
    final result =
        await RemoteCustomerRepository(api).list(search: 'David', page: 2);
    expect(result.customers.single.id, '88');
    expect(result.customers.single.ticketsCount, 4);
    expect(result.page, 2);
    expect(result.lastPage, 4);
    expect(adapter.requests.single.queryParameters,
        {'search': 'David', 'page': 2, 'per_page': 20});
    expect(adapter.requests.single.headers['X-Workspace-Id'], '9');
    expect(adapter.requests.single.headers['Authorization'],
        'Bearer session-token');
  });

  test('profile parses ticket and call history including missing recording',
      () async {
    final adapter = _JsonAdapter('''
      {"customer":{"id":88,"name":"David Mwangi","phone_number":"+254768270973",
      "email":"david@example.com","company":"Nairobi Tech Ltd","tickets":[
      {"id":14,"display_number":"#TKT-14","subject":"Change email","status":"open",
      "priority":"low","source":"whatsapp","created_at":"2026-08-31T07:38:00Z"}]},
      "call_logs":[{"id":6,"direction":"inbound","status":"missed","duration":41,
      "from_number":"+254743379990","to_number":"+254709369917","recording_url":null,
      "agent":{"id":4,"name":"Alice Agent"},"created_at":"2026-09-21T15:22:04+03:00",
      "ended_at":"2026-09-21T15:22:45+03:00"}]}
    ''');
    final profile = await RemoteCustomerRepository(_api(adapter)).profile('88');
    expect(adapter.requests.single.path, '/customers/88');
    expect(profile.customer.company, 'Nairobi Tech Ltd');
    expect(profile.tickets.single.displayNumber, '#TKT-14');
    expect(profile.callLogs.single.status, 'missed');
    expect(profile.callLogs.single.durationSeconds, 41);
    expect(profile.callLogs.single.agentName, 'Alice Agent');
    expect(profile.callLogs.single.recordingUrl, isNull);
    expect(profile.callLogs.single.createdAt, isNotNull);
  });

  test('malformed customer profile throws a safe format exception', () async {
    final repository =
        RemoteCustomerRepository(_api(_JsonAdapter('{"ok":true}')));
    expect(repository.profile('88'), throwsA(isA<FormatException>()));
  });
}

ApiService _api(_JsonAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
    ..httpClientAdapter = adapter;
  return ApiService(
    baseUrl: 'https://api.example.test',
    dio: dio,
    readAccessToken: () => 'session-token',
    readWorkspaceId: () => '9',
    onUnauthorized: () async {},
  );
}
