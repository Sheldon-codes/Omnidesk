import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/api_service.dart';
import '../../services/auth_session_controller.dart';
import '../../services/response_cache.dart';
import '../customer_editor_page/customer_editor_page_model.dart';

part 'customer_repository.g.dart';

class CustomerPageResult {
  const CustomerPageResult({
    required this.customers,
    required this.page,
    required this.lastPage,
    required this.total,
  });

  final List<CustomerRecord> customers;
  final int page;
  final int lastPage;
  final int total;
}

class CustomerProfile {
  const CustomerProfile({
    required this.customer,
    required this.tickets,
    required this.callLogs,
  });

  final CustomerRecord customer;
  final List<CustomerProfileTicket> tickets;
  final List<CustomerCallLog> callLogs;
}

class CustomerCallLog {
  const CustomerCallLog({
    required this.id,
    required this.direction,
    required this.status,
    required this.durationSeconds,
    required this.fromNumber,
    required this.toNumber,
    required this.recordingUrl,
    required this.agentName,
    required this.createdAt,
    required this.endedAt,
  });

  final String id;
  final String direction;
  final String status;
  final int? durationSeconds;
  final String fromNumber;
  final String toNumber;
  final String? recordingUrl;
  final String? agentName;
  final DateTime? createdAt;
  final DateTime? endedAt;
}

class CustomerProfileTicket {
  const CustomerProfileTicket({
    required this.id,
    required this.displayNumber,
    required this.subject,
    required this.status,
    required this.priority,
    required this.source,
    required this.createdAt,
  });

  final String id;
  final String displayNumber;
  final String subject;
  final String status;
  final String priority;
  final String source;
  final DateTime? createdAt;
}

abstract interface class CustomerRepository {
  Future<CustomerPageResult> list({
    String search = '',
    int page = 1,
    int perPage = 20,
    CancelToken? cancelToken,
    void Function(CustomerPageResult value)? onCached,
    void Function()? onCacheMiss,
  });

  Future<CustomerProfile> profile(
    String id, {
    CancelToken? cancelToken,
    void Function(CustomerProfile value)? onCached,
    void Function()? onCacheMiss,
  });

  Future<CustomerRecord> update(
    String id, {
    required Map<String, Object?> fields,
    required CustomerRecord fallback,
    CancelToken? cancelToken,
  });
}

class RemoteCustomerRepository implements CustomerRepository {
  RemoteCustomerRepository(this._api,
      {ResponseCache? cache, ResponseCacheScope? Function()? readScope})
      : _cache = cache,
        _readScope = readScope;

  final ApiService _api;
  final ResponseCache? _cache;
  final ResponseCacheScope? Function()? _readScope;

  @override
  Future<CustomerRecord> update(
    String id, {
    required Map<String, Object?> fields,
    required CustomerRecord fallback,
    CancelToken? cancelToken,
  }) async {
    if (fields.isEmpty) return fallback;
    final raw = await _api.put(
      '/customers/${Uri.encodeComponent(id)}',
      fields.cast<String, dynamic>(),
      cancelToken: cancelToken,
    );
    final root = _map(raw, 'customer update response');
    final customerJson = root['customer'];
    if (customerJson is! Map) {
      throw const FormatException('Updated customer is missing.');
    }
    final json = _map(customerJson, 'updated customer');
    final updated = _mergeUpdatedCustomer(json, fallback);
    final cache = _cache;
    final scope = _readScope?.call();
    if (cache != null && scope != null) {
      final epoch = cache.writeEpoch;
      await cache.updateModuleJson(
        scope: scope,
        module: 'customers',
        expectedEpoch: epoch,
        update: (key, snapshot) {
          if (snapshot is! Map) return snapshot;
          final root = Map<String, dynamic>.from(
            snapshot.map((key, value) => MapEntry(key.toString(), value)),
          );
          if (key.startsWith('profile:')) {
            final cachedCustomer = root['customer'];
            if (cachedCustomer is! Map || _string(cachedCustomer['id']) != id) {
              return snapshot;
            }
            root['customer'] = {
              ...Map<String, dynamic>.from(cachedCustomer.map(
                (key, value) => MapEntry(key.toString(), value),
              )),
              ...json,
            };
            return root;
          }
          final data = root['data'];
          if (data is List) {
            root['data'] = data.map((row) {
              if (row is! Map || _string(row['id']) != id) return row;
              return {
                ...Map<String, dynamic>.from(row.map(
                  (key, value) => MapEntry(key.toString(), value),
                )),
                ...json,
              };
            }).toList(growable: false);
            return root;
          }
          return snapshot;
        },
      );
    }
    return updated;
  }

  @override
  Future<CustomerPageResult> list({
    String search = '',
    int page = 1,
    int perPage = 20,
    CancelToken? cancelToken,
    void Function(CustomerPageResult value)? onCached,
    void Function()? onCacheMiss,
  }) async {
    final parameters = <String, Object?>{
      if (search.trim().isNotEmpty) 'search': search.trim(),
      'page': page,
      'per_page': perPage,
    };
    final cache = _cache;
    final scope = _readScope?.call();
    if (cache != null && scope != null) {
      return (await CacheFirstJsonLoader(cache).load(
        scope: scope,
        module: 'customers',
        key: 'list?${stableCacheQueryKey(parameters)}',
        expectedEpoch: cache.writeEpoch,
        fetch: () => _api.get('/customers',
            queryParameters: parameters, cancelToken: cancelToken),
        decode: (raw) => _decodeList(raw, page),
        onCached: onCached ?? (_) {},
        onFresh: (_) {},
        onCacheMiss: onCacheMiss,
      ))
          .value;
    }
    return _decodeList(
      await _api.get('/customers',
          queryParameters: parameters, cancelToken: cancelToken),
      page,
    );
  }

  static CustomerPageResult _decodeList(dynamic raw, int page) {
    final root = _map(raw, 'customer list response');
    final rows = root['data'];
    if (rows is! List) {
      throw const FormatException('Customers data is missing.');
    }
    final meta = root['meta'] is Map
        ? _map(root['meta'], 'customer page meta')
        : const <String, dynamic>{};
    final customers = rows
        .map((row) => _customer(_map(row, 'customer row')))
        .toList(growable: false);
    return CustomerPageResult(
      customers: customers,
      page: _int(meta['current_page'], page),
      lastPage: _int(meta['last_page'], page),
      total: _int(meta['total'], customers.length),
    );
  }

  @override
  Future<CustomerProfile> profile(String id,
      {CancelToken? cancelToken,
      void Function(CustomerProfile value)? onCached,
      void Function()? onCacheMiss}) async {
    final cache = _cache;
    final scope = _readScope?.call();
    if (cache != null && scope != null) {
      return (await CacheFirstJsonLoader(cache).load(
        scope: scope,
        module: 'customers',
        key: 'profile:$id',
        expectedEpoch: cache.writeEpoch,
        fetch: () => _api.get('/customers/${Uri.encodeComponent(id)}',
            cancelToken: cancelToken),
        decode: _decodeProfile,
        onCached: onCached ?? (_) {},
        onFresh: (_) {},
        onCacheMiss: onCacheMiss,
      ))
          .value;
    }
    return _decodeProfile(await _api.get(
        '/customers/${Uri.encodeComponent(id)}',
        cancelToken: cancelToken));
  }

  static CustomerProfile _decodeProfile(dynamic raw) {
    final root = _map(raw, 'customer profile response');
    final customerJson = root['customer'];
    if (customerJson is! Map) {
      throw const FormatException('Customer profile is missing.');
    }
    final map = _map(customerJson, 'customer profile');
    final ticketsRaw = map['tickets'];
    final tickets = ticketsRaw is List
        ? ticketsRaw
            .map((ticket) => _ticket(_map(ticket, 'customer ticket')))
            .toList(growable: false)
        : const <CustomerProfileTicket>[];
    final callsRaw = root['call_logs'];
    final callLogs = callsRaw is List
        ? callsRaw
            .map((call) => _callLog(_map(call, 'customer call log')))
            .toList(growable: false)
        : const <CustomerCallLog>[];
    return CustomerProfile(
      customer: _customer(map),
      tickets: tickets,
      callLogs: callLogs,
    );
  }

  static CustomerRecord _customer(Map<String, dynamic> json) => CustomerRecord(
        id: _requiredString(json['id'], 'customer id'),
        name: _string(json['name']),
        phone: _string(json['phone_number']),
        email: _string(json['email']),
        company: _string(json['company']),
        notes: _string(json['notes']),
        tags: json['tags'] is List
            ? (json['tags'] as List).map((tag) => tag.toString()).toList()
            : const [],
        ticketsCount: json['tickets_count'] == null
            ? null
            : _int(json['tickets_count'], 0),
        createdAt: DateTime.tryParse(_string(json['created_at']))?.toUtc(),
      );

  static CustomerRecord _mergeUpdatedCustomer(
    Map<String, dynamic> json,
    CustomerRecord fallback,
  ) =>
      CustomerRecord(
        id: _string(json['id']).ifEmpty(fallback.id),
        name: json.containsKey('name') ? _string(json['name']) : fallback.name,
        phone: json.containsKey('phone_number')
            ? _string(json['phone_number'])
            : fallback.phone,
        email:
            json.containsKey('email') ? _string(json['email']) : fallback.email,
        company: json.containsKey('company')
            ? _string(json['company'])
            : fallback.company,
        notes:
            json.containsKey('notes') ? _string(json['notes']) : fallback.notes,
        tags: json['tags'] is List
            ? (json['tags'] as List).map((tag) => tag.toString()).toList()
            : fallback.tags,
        ticketsCount: json['tickets_count'] == null
            ? fallback.ticketsCount
            : _int(json['tickets_count'], fallback.ticketsCount ?? 0),
        createdAt: DateTime.tryParse(_string(json['created_at']))?.toUtc() ??
            fallback.createdAt,
      );

  static CustomerProfileTicket _ticket(Map<String, dynamic> json) =>
      CustomerProfileTicket(
        id: _requiredString(json['id'], 'ticket id'),
        displayNumber:
            _string(json['display_number']).ifEmpty('#${json['id']}'),
        subject: _string(json['subject']).ifEmpty('Untitled ticket'),
        status: _string(json['status']).ifEmpty('unknown'),
        priority: _string(json['priority']).ifEmpty('unknown'),
        source: _string(json['source']).ifEmpty('unknown'),
        createdAt: DateTime.tryParse(_string(json['created_at']))?.toUtc(),
      );

  static CustomerCallLog _callLog(Map<String, dynamic> json) {
    final agent = json['agent'] is Map
        ? _map(json['agent'], 'call agent')
        : const <String, dynamic>{};
    return CustomerCallLog(
      id: _requiredString(json['id'], 'call log id'),
      direction: _string(json['direction']).ifEmpty('unknown'),
      status: _string(json['status']).ifEmpty('unknown'),
      durationSeconds:
          json['duration'] == null ? null : _int(json['duration'], 0),
      fromNumber: _string(json['from_number']),
      toNumber: _string(json['to_number']),
      recordingUrl: _nullableString(json['recording_url']),
      agentName: _nullableString(agent['name']),
      createdAt: DateTime.tryParse(_string(json['created_at']))?.toUtc(),
      endedAt: DateTime.tryParse(_string(json['ended_at']))?.toUtc(),
    );
  }

  static Map<String, dynamic> _map(dynamic value, String label) {
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    throw FormatException('Invalid $label.');
  }

  static String _requiredString(dynamic value, String label) {
    final result = value?.toString().trim() ?? '';
    if (result.isEmpty) throw FormatException('Missing $label.');
    return result;
  }

  static String _string(dynamic value) => value?.toString().trim() ?? '';
  static String? _nullableString(dynamic value) {
    final string = _string(value);
    return string.isEmpty ? null : string;
  }

  static int _int(dynamic value, int fallback) =>
      int.tryParse(value?.toString() ?? '') ?? fallback;
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

@Riverpod(keepAlive: true)
CustomerRepository customerRepository(Ref ref) => RemoteCustomerRepository(
      ref.watch(apiServiceProvider),
      cache: ref.watch(responseCacheProvider),
      readScope: () {
        final user = ref.read(authSessionControllerProvider).session?.user;
        return user == null ? null : ResponseCacheScope.fromUser(user);
      },
    );
