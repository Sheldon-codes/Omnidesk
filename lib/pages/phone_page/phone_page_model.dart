import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/calls/call_log_store.dart';
import '../../services/calls/call_models.dart';
import '../customer_editor_page/customer_editor_page_model.dart' as customers;

part 'phone_page_model.g.dart';

enum PhoneTab { recents, contacts }

/// Presentation model for a call-history record. Its list remains empty until
/// the calls API exposes a documented history endpoint; keeping the typed
/// projection lets the existing rows, accessibility labels, and swipe actions
/// render server-backed records without another UI rewrite.
enum PhoneCallDirection { missed, inbound, outbound }

enum PhoneViewMode { list, dialPad }

class PhoneRecent {
  const PhoneRecent({
    required this.name,
    required this.phone,
    required this.time,
    required this.detail,
    this.direction = PhoneCallDirection.inbound,
    this.ticket,
    this.recordingUrl,
  });

  final String name;
  final String phone;
  final String time;
  final String detail;
  final PhoneCallDirection direction;
  final String? ticket;
  final String? recordingUrl;

  /// A recording control is shown only for answered server records.
  bool get isAnswered =>
      direction != PhoneCallDirection.missed &&
      RegExp(r'^\d+:\d{2}$').hasMatch(detail.trim());

  bool get hasRecording {
    final uri = Uri.tryParse(recordingUrl ?? '');
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http');
  }

  factory PhoneRecent.fromCallLog(CallLogRecord record) => PhoneRecent(
        name: record.customerName?.trim().isNotEmpty == true
            ? record.customerName!.trim()
            : record.phoneNumber,
        phone: record.phoneNumber,
        time: _timeLabel(record.occurredAt),
        detail: _detailLabel(record),
        direction: switch (record.status) {
          CallLogStatus.missed => PhoneCallDirection.missed,
          _ when record.direction == CallDirection.outbound =>
            PhoneCallDirection.outbound,
          _ => PhoneCallDirection.inbound,
        },
        ticket: record.ticketNumber,
        recordingUrl: record.recordingUrl,
      );

  static String _timeLabel(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  static String _detailLabel(CallLogRecord record) {
    if (record.status == CallLogStatus.missed) return 'Missed';
    if (record.status == CallLogStatus.failed) return 'Failed';
    if (record.status == CallLogStatus.cancelled) return 'Cancelled';
    final formattedDuration = record.formattedDuration?.trim();
    if (formattedDuration != null &&
        RegExp(r'^\d+:\d{2}(?::\d{2})?$').hasMatch(formattedDuration)) {
      return formattedDuration;
    }
    final minutes = record.duration.inMinutes;
    final seconds =
        record.duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class PhoneContact {
  const PhoneContact({
    this.name,
    required this.identifier,
    this.avatar,
    this.ticketCount,
    this.id,
  });

  final String? name;
  final String identifier;
  final String? avatar;
  final int? ticketCount;
  final String? id;

  factory PhoneContact.fromCustomer(customers.CustomerRecord customer) =>
      PhoneContact(
        id: customer.id,
        name: customer.name.isEmpty ? null : customer.name,
        identifier: customer.phone.isNotEmpty ? customer.phone : customer.email,
      );

  String get title =>
      name?.trim().isNotEmpty == true ? name!.trim() : identifier;
  String get subtitle => name?.trim().isNotEmpty == true
      ? identifier
      : ticketCount == null
          ? 'No tickets yet'
          : identifier;
  String get initials => title.runes.isEmpty
      ? '?'
      : String.fromCharCode(title.runes.first).toUpperCase();
}

class PhonePageState {
  const PhonePageState({
    this.tab = PhoneTab.recents,
    this.viewMode = PhoneViewMode.list,
    this.searchActive = false,
    this.query = '',
    this.dialedNumber = '',
    this.recents = const [],
    this.contacts = const [],
    this.historyLoading = false,
    this.historyRefreshing = false,
    this.historyLoadingMore = false,
    this.historyHasMore = false,
    this.historyError,
  });

  final PhoneTab tab;
  final PhoneViewMode viewMode;
  final bool searchActive;
  final String query;
  final String dialedNumber;
  final List<PhoneRecent> recents;
  final List<PhoneContact> contacts;
  final bool historyLoading;
  final bool historyRefreshing;
  final bool historyLoadingMore;
  final bool historyHasMore;
  final String? historyError;

  String get subtitle => tab == PhoneTab.recents
      ? 'Call history'
      : '${contacts.length} ${contacts.length == 1 ? 'contact' : 'contacts'}';

  PhoneContact? get matchedContact {
    final normalized = _digitsOnly(dialedNumber);
    if (normalized.isEmpty) return null;
    for (final contact in contacts) {
      final candidate = _digitsOnly(contact.identifier);
      if (candidate.isNotEmpty &&
          (candidate.contains(normalized) || normalized.contains(candidate))) {
        return contact;
      }
    }
    return null;
  }

  List<PhoneRecent> get filteredRecents {
    final query = this.query.trim().toLowerCase();
    if (query.isEmpty) return recents;
    return recents
        .where((recent) => _matches(query, [
              recent.name,
              recent.phone,
              recent.time,
              recent.detail,
              recent.ticket ?? '',
            ]))
        .toList(growable: false);
  }

  List<PhoneContact> get filteredContacts {
    final query = this.query.trim().toLowerCase();
    if (query.isEmpty) return contacts;
    return contacts
        .where((contact) => _matches(query, [
              contact.name ?? '',
              contact.identifier,
            ]))
        .toList(growable: false);
  }

  PhonePageState copyWith({
    PhoneTab? tab,
    PhoneViewMode? viewMode,
    bool? searchActive,
    String? query,
    String? dialedNumber,
    bool? historyLoading,
    bool? historyRefreshing,
    bool? historyLoadingMore,
    bool? historyHasMore,
    Object? historyError = _keep,
  }) =>
      PhonePageState(
        tab: tab ?? this.tab,
        viewMode: viewMode ?? this.viewMode,
        searchActive: searchActive ?? this.searchActive,
        query: query ?? this.query,
        dialedNumber: dialedNumber ?? this.dialedNumber,
        recents: recents,
        contacts: contacts,
        historyLoading: historyLoading ?? this.historyLoading,
        historyRefreshing: historyRefreshing ?? this.historyRefreshing,
        historyLoadingMore: historyLoadingMore ?? this.historyLoadingMore,
        historyHasMore: historyHasMore ?? this.historyHasMore,
        historyError: identical(historyError, _keep)
            ? this.historyError
            : historyError as String?,
      );

  static const _keep = Object();
  static bool _matches(String query, Iterable<String> values) =>
      values.any((value) => value.toLowerCase().contains(query));

  static String _digitsOnly(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');
}

@riverpod
class PhonePageNotifier extends _$PhonePageNotifier {
  @override
  PhonePageState build() {
    final callHistory = ref.watch(callLogStoreProvider);
    return PhonePageState(
      recents: callHistory.records
          .map(PhoneRecent.fromCallLog)
          .toList(growable: false),
      contacts: ref
          .watch(customers.customersStoreProvider)
          .map(PhoneContact.fromCustomer)
          .toList(growable: false),
      historyLoading: callHistory.loading,
      historyRefreshing: callHistory.refreshing,
      historyLoadingMore: callHistory.loadingMore,
      historyHasMore: callHistory.hasMore,
      historyError: callHistory.error,
    );
  }

  void selectTab(PhoneTab tab) {
    state = state.copyWith(tab: tab, searchActive: false, query: '');
  }

  void openDialPad() => state = state.copyWith(
        viewMode: PhoneViewMode.dialPad,
        searchActive: false,
        query: '',
      );

  void closeDialPad() => state = state.copyWith(
        viewMode: PhoneViewMode.list,
        dialedNumber: '',
      );

  void appendDigit(String digit) {
    if (!RegExp(r'^[0-9*#]$').hasMatch(digit)) return;
    state = state.copyWith(dialedNumber: '${state.dialedNumber}$digit');
  }

  void deleteLastDigit() {
    if (state.dialedNumber.isEmpty) return;
    state = state.copyWith(
        dialedNumber:
            state.dialedNumber.substring(0, state.dialedNumber.length - 1));
  }

  void clearDialedNumber() => state = state.copyWith(dialedNumber: '');

  void openSearch() => state = state.copyWith(searchActive: true);

  void closeSearch() => state = state.copyWith(searchActive: false, query: '');

  void setSearchQuery(String value) => state = state.copyWith(query: value);
}
