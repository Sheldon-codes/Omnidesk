import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'phone_page_model.g.dart';

enum PhoneTab { recents, contacts }

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
  });

  final String name;
  final String phone;
  final String time;
  final String detail;
  final PhoneCallDirection direction;
  final String? ticket;
}

class PhoneContact {
  const PhoneContact({
    this.name,
    required this.identifier,
    this.avatar,
    this.ticketCount,
  });

  final String? name;
  final String identifier;
  final String? avatar;
  final int? ticketCount;

  String get title =>
      name?.trim().isNotEmpty == true ? name!.trim() : identifier;
  String get subtitle => name?.trim().isNotEmpty == true
      ? identifier
      : ticketCount == null
          ? 'No tickets yet'
          : identifier;
  String get initials => title.substring(0, 1).toUpperCase();
}

class PhonePageState {
  const PhonePageState({
    this.tab = PhoneTab.recents,
    this.viewMode = PhoneViewMode.list,
    this.searchActive = false,
    this.query = '',
    this.dialedNumber = '',
    this.recents = _defaultRecents,
    this.contacts = _defaultContacts,
  });

  final PhoneTab tab;
  final PhoneViewMode viewMode;
  final bool searchActive;
  final String query;
  final String dialedNumber;
  final List<PhoneRecent> recents;
  final List<PhoneContact> contacts;

  String get subtitle =>
      tab == PhoneTab.recents ? '9 calls today · 3 missed' : '192 contacts';

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
  }) =>
      PhonePageState(
        tab: tab ?? this.tab,
        viewMode: viewMode ?? this.viewMode,
        searchActive: searchActive ?? this.searchActive,
        query: query ?? this.query,
        dialedNumber: dialedNumber ?? this.dialedNumber,
        recents: recents,
        contacts: contacts,
      );

  static bool _matches(String query, Iterable<String> values) =>
      values.any((value) => value.toLowerCase().contains(query));

  static String _digitsOnly(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');
}

const _defaultRecents = <PhoneRecent>[
  PhoneRecent(
    name: 'Caller 1967',
    phone: '+254720261967',
    time: '09:50',
    detail: 'failed',
    direction: PhoneCallDirection.missed,
    ticket: 'DGKSL-378',
  ),
  PhoneRecent(
    name: 'Fidel Wisdom Park',
    phone: '0743424985',
    time: '12:29',
    detail: '1:03',
  ),
  PhoneRecent(
    name: 'Caller 5538',
    phone: '+254754375538',
    time: '12:09',
    detail: 'missed',
    direction: PhoneCallDirection.missed,
    ticket: 'DGKSL-373',
  ),
  PhoneRecent(
    name: 'Hillary Cheserek',
    phone: '0720228448',
    time: '11:56',
    detail: 'missed',
    direction: PhoneCallDirection.missed,
  ),
  PhoneRecent(
    name: 'Unknown caller',
    phone: '0714474457',
    time: '11:55',
    detail: '0:10',
    direction: PhoneCallDirection.outbound,
  ),
];

const _defaultContacts = <PhoneContact>[
  PhoneContact(
    name: 'Caller 1967',
    identifier: '+254720261967',
    ticketCount: 1,
  ),
  PhoneContact(
    name: '😎',
    identifier: '+254721161652',
    avatar: '😎',
    ticketCount: 1,
  ),
  PhoneContact(identifier: '+29454885757108'),
  PhoneContact(
    name: 'Nana',
    identifier: '+254719106280',
    ticketCount: 1,
  ),
  PhoneContact(identifier: '+43907731261010'),
  PhoneContact(
    name: 'otieno',
    identifier: 'sullyvan83@gmail.com',
    ticketCount: 1,
  ),
];

@riverpod
class PhonePageNotifier extends _$PhonePageNotifier {
  @override
  PhonePageState build() => const PhonePageState();

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
