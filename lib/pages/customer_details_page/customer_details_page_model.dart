import 'dart:async';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/api_service.dart';
import '../../services/auth_session_controller.dart';
import '../customer_editor_page/customer_editor_page_model.dart';
import '../customers_page/customer_repository.dart';

part 'customer_details_page_model.g.dart';

class CustomerDetailTicket {
  const CustomerDetailTicket({
    required this.id,
    required this.displayNumber,
    required this.subject,
    required this.status,
    required this.priority,
    required this.source,
    this.createdAt,
  });

  final String id;
  final String displayNumber;
  final String subject;
  final String status;
  final String priority;
  final String source;
  final DateTime? createdAt;
}

class CustomerDetailCallLog {
  const CustomerDetailCallLog({
    required this.id,
    required this.direction,
    required this.status,
    required this.fromNumber,
    required this.toNumber,
    required this.durationSeconds,
    required this.recordingUrl,
    required this.agentName,
    required this.createdAt,
    required this.endedAt,
  });

  final String id;
  final String direction;
  final String status;
  final String fromNumber;
  final String toNumber;
  final int? durationSeconds;
  final String? recordingUrl;
  final String? agentName;
  final DateTime? createdAt;
  final DateTime? endedAt;
}

class CustomerDetailState {
  const CustomerDetailState({
    required this.customerId,
    this.customer,
    this.tickets = const [],
    this.callLogs = const [],
    this.loading = false,
    this.hasLoaded = false,
    this.error,
  });

  final String customerId;
  final CustomerRecord? customer;
  final List<CustomerDetailTicket> tickets;
  final List<CustomerDetailCallLog> callLogs;
  final bool loading;
  final bool hasLoaded;
  final String? error;

  bool get notFound => hasLoaded && customer == null && error == null;
  bool get hasIdentity => customer != null;

  CustomerDetailState copyWith({
    CustomerRecord? customer,
    List<CustomerDetailTicket>? tickets,
    List<CustomerDetailCallLog>? callLogs,
    bool? loading,
    bool? hasLoaded,
    Object? error = _keep,
  }) =>
      CustomerDetailState(
        customerId: customerId,
        customer: customer ?? this.customer,
        tickets: tickets ?? this.tickets,
        callLogs: callLogs ?? this.callLogs,
        loading: loading ?? this.loading,
        hasLoaded: hasLoaded ?? this.hasLoaded,
        error: identical(error, _keep) ? this.error : error as String?,
      );

  static const _keep = Object();
}

@Riverpod(keepAlive: true)
class CustomerDetailNotifier extends _$CustomerDetailNotifier {
  CancelToken? _request;
  int _generation = 0;
  String? _sessionScope;

  @override
  CustomerDetailState build({required String customerId}) {
    final auth = ref.watch(authSessionControllerProvider);
    final scope =
        '${auth.session?.user.id ?? 'anonymous'}:${auth.session?.user.activeWorkspace?.id ?? 'none'}';
    final changedScope = _sessionScope != null && _sessionScope != scope;
    if (changedScope) {
      _generation++;
      _cancelRequest('Customer workspace changed.');
    }
    _sessionScope = scope;
    final cached = changedScope
        ? null
        : ref
            .read(customersStoreProvider)
            .where((customer) => customer.id == customerId)
            .firstOrNull;
    ref.onDispose(() => _cancelRequest('Customer details no longer observed.'));
    scheduleMicrotask(() {
      if (ref.mounted) unawaited(load());
    });
    return CustomerDetailState(
      customerId: customerId,
      customer: cached,
      loading: true,
    );
  }

  void seedCustomer(CustomerRecord customer) {
    if (customer.id != customerId) return;
    state = state.copyWith(customer: customer);
  }

  Future<void> load() async {
    _cancelRequest('Customer profile refresh superseded request.');
    final token = CancelToken();
    _request = token;
    final generation = ++_generation;
    state = state.copyWith(loading: true, error: null);
    try {
      final profile = await ref.read(customerRepositoryProvider).profile(
        customerId,
        cancelToken: token,
        onCacheMiss: () {
          if (generation == _generation && state.customer == null) {
            state = state.copyWith(loading: true);
          }
        },
        onCached: (cached) {
          if (generation == _generation) {
            _publishProfile(cached, loading: true);
          }
        },
      );
      if (generation != _generation) return;
      _publishProfile(profile, loading: false);
    } catch (error) {
      if ((error is DioException && CancelToken.isCancel(error)) ||
          generation != _generation) {
        return;
      }
      final notFound = error is ApiClientException && error.statusCode == 404;
      state = state.copyWith(
        loading: false,
        hasLoaded: true,
        error: notFound
            ? null
            : error is FormatException
                ? 'The server returned an unexpected customer profile.'
                : error.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  void _cancelRequest(Object reason) {
    final request = _request;
    if (request != null && !request.isCancelled) request.cancel(reason);
  }

  void _publishProfile(CustomerProfile profile, {required bool loading}) {
    ref.read(customersStoreProvider.notifier).upsert(profile.customer);
    state = CustomerDetailState(
      customerId: customerId,
      customer: profile.customer,
      tickets: profile.tickets
          .map((ticket) => CustomerDetailTicket(
                id: ticket.id,
                displayNumber: ticket.displayNumber,
                subject: ticket.subject,
                status: ticket.status,
                priority: ticket.priority,
                source: ticket.source,
                createdAt: ticket.createdAt,
              ))
          .toList(growable: false),
      callLogs: profile.callLogs
          .map((call) => CustomerDetailCallLog(
                id: call.id,
                direction: call.direction,
                status: call.status,
                fromNumber: call.fromNumber,
                toNumber: call.toNumber,
                durationSeconds: call.durationSeconds,
                recordingUrl: call.recordingUrl,
                agentName: call.agentName,
                createdAt: call.createdAt,
                endedAt: call.endedAt,
              ))
          .toList(growable: false),
      loading: loading,
      hasLoaded: true,
    );
  }
}
