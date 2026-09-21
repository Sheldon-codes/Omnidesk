// Typed domain contracts for the native mobile call flow. These types
// deliberately model the server's canonical IDs instead of leaking provider
// (Africa's Talking) identifiers through the UI layer.

typedef CallId = String;
typedef CallOfferId = String;

enum CallDirection { inbound, outbound }

enum CallLogStatus { completed, missed, failed, cancelled, unknown }

enum CallPhase {
  idle,
  incomingRinging,
  outgoingPreparing,
  outgoingRinging,
  accepted,
  mediaPreparing,
  connecting,
  active,
  held,
  ending,
  completed,
  declined,
  missed,
  cancelled,
  failed,
  expired,
  answeredElsewhere,
}

class CallOffer {
  const CallOffer({
    required this.callId,
    required this.offerId,
    required this.provider,
    required this.callerNumber,
    required this.workspaceId,
    required this.receivedAt,
    required this.expiresAt,
    this.eventId,
    this.providerCallId,
    this.callerName,
    this.customerId,
    this.ticketId,
    this.ticketNumber,
    this.category,
  });

  final CallId callId;
  final CallOfferId offerId;
  final String provider;
  final String? providerCallId;
  final String callerNumber;
  final String? callerName;
  final String? customerId;
  final String? ticketId;
  final String? ticketNumber;
  final String? category;
  final String workspaceId;
  final DateTime receivedAt;
  final DateTime expiresAt;

  /// Transport identity. It is intentionally distinct from the offer identity:
  /// cancellation events refer to the same offer but must still be processed.
  final String? eventId;

  bool get isExpired => !expiresAt.isAfter(DateTime.now().toUtc());

  factory CallOffer.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(Object? value, {required DateTime fallback}) =>
        DateTime.tryParse(value?.toString() ?? '')?.toUtc() ?? fallback;
    final now = DateTime.now().toUtc();
    return CallOffer(
      callId: '${json['call_id'] ?? ''}',
      offerId: '${json['offer_id'] ?? ''}',
      provider: '${json['provider'] ?? ''}',
      providerCallId: json['provider_call_id']?.toString(),
      callerNumber: '${json['caller_number'] ?? ''}',
      callerName: json['caller_name']?.toString(),
      customerId: json['customer_id']?.toString(),
      ticketId: json['ticket_id']?.toString(),
      ticketNumber: json['ticket_number']?.toString(),
      category: json['category']?.toString(),
      workspaceId: '${json['workspace_id'] ?? ''}',
      receivedAt: parseDate(json['timestamp'], fallback: now),
      expiresAt: parseDate(
        json['expires_at'],
        fallback: now.add(const Duration(seconds: 30)),
      ),
      eventId: json['event_id']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': 'incoming_call',
        'call_id': callId,
        'offer_id': offerId,
        'provider': provider,
        'provider_call_id': providerCallId,
        'caller_number': callerNumber,
        'caller_name': callerName,
        'customer_id': customerId,
        'ticket_id': ticketId,
        'ticket_number': ticketNumber,
        'category': category,
        'workspace_id': workspaceId,
        'timestamp': receivedAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
        if (eventId != null) 'event_id': eventId,
      };
}

class CallMediaConfig {
  const CallMediaConfig({
    required this.provider,
    required this.transport,
    required this.endpointType,
    required this.sipUri,
    required this.sipUsername,
    required this.sipAuthUsername,
    required this.registrar,
    required this.sipDomain,
    required this.sipProxy,
    required this.sipTransport,
    required this.port,
    required this.supportsHold,
    required this.supportsDtmf,
    required this.supportsNativeIncoming,
    this.sipPassword,
    this.webrtcToken,
    this.webrtcGatewayUrl,
    this.webrtcClientName,
  });

  final String provider;
  final String transport;
  final String endpointType;
  final String sipUri;
  final String sipUsername;
  final String sipAuthUsername;
  final String registrar;
  final String sipDomain;
  final String sipProxy;
  final String sipTransport;
  final int port;
  final String? sipPassword;
  final bool supportsHold;
  final bool supportsDtmf;
  final bool supportsNativeIncoming;

  /// Africa's Talking WebRTC gateway credentials (browser-softphone path).
  /// Null unless the backend returns a `webrtc` block; the hidden-WebView
  /// media engine consumes these, never the SIP fields above.
  final String? webrtcToken;
  final String? webrtcGatewayUrl;
  final String? webrtcClientName;

  /// A native SIP stack must reject incomplete configuration rather than
  /// falling back to anonymous or non-TLS registration. These credentials are
  /// deliberately ephemeral and are never persisted by the Dart layer.
  bool get canAuthenticate =>
      provider == 'africas_talking' &&
      transport == 'sip' &&
      endpointType == 'mobile' &&
      sipUri.isNotEmpty &&
      sipUsername.isNotEmpty &&
      sipAuthUsername.isNotEmpty &&
      sipPassword != null &&
      sipPassword!.isNotEmpty &&
      registrar.isNotEmpty &&
      sipDomain.isNotEmpty &&
      sipProxy.isNotEmpty &&
      sipTransport.toLowerCase() == 'tls' &&
      port > 0;

  factory CallMediaConfig.fromJson(Map<String, dynamic> json) {
    final sip = json['sip'] is Map
        ? (json['sip'] as Map).map((key, value) => MapEntry('$key', value))
        : const <String, dynamic>{};
    final webrtc = json['webrtc'] is Map
        ? (json['webrtc'] as Map).map((key, value) => MapEntry('$key', value))
        : const <String, dynamic>{};
    final capabilities = json['capabilities'] is Map
        ? (json['capabilities'] as Map)
            .map((key, value) => MapEntry('$key', value))
        : const <String, dynamic>{};
    bool boolValue(Object? value) =>
        value == true || value == 1 || value == '1';
    return CallMediaConfig(
      provider: '${json['provider'] ?? ''}',
      transport: '${json['transport'] ?? ''}',
      endpointType: '${json['endpoint_type'] ?? ''}',
      sipUri: '${sip['uri'] ?? ''}',
      sipUsername: '${sip['username'] ?? ''}',
      sipAuthUsername: '${sip['auth_username'] ?? sip['username'] ?? ''}',
      registrar: '${sip['registrar'] ?? ''}',
      sipDomain: '${sip['domain'] ?? sip['registrar'] ?? ''}',
      sipProxy: '${sip['proxy'] ?? ''}',
      sipTransport: '${sip['transport'] ?? ''}',
      port: int.tryParse('${sip['port'] ?? ''}') ?? 0,
      sipPassword:
          (sip['password'] ?? sip['credential'] ?? sip['token'])?.toString(),
      supportsHold: boolValue(capabilities['hold']),
      supportsDtmf: boolValue(capabilities['dtmf']),
      supportsNativeIncoming: boolValue(capabilities['native_incoming']),
      webrtcToken: (webrtc['token'])?.toString(),
      webrtcGatewayUrl:
          (webrtc['gateway_url'] ?? webrtc['gatewayUrl'])?.toString(),
      webrtcClientName:
          (webrtc['client_name'] ?? webrtc['clientName'])?.toString(),
    );
  }

  /// The hidden-WebView engine is usable when a capability token exists.
  /// The gateway URL is optional: the AT JS client defaults to the
  /// production gateway when none is supplied.
  bool get canUseWebRtc =>
      provider == 'africas_talking' &&
      (webrtcToken != null && webrtcToken!.isNotEmpty);
}

class ActiveCallSnapshot {
  const ActiveCallSnapshot({
    required this.callId,
    required this.direction,
    required this.phase,
    required this.remoteNumber,
    required this.createdAt,
    this.customerId,
    this.customerName,
    this.ticketId,
    this.ticketNumber,
    this.category,
    this.offerId,
    this.answeredAt,
  });

  final CallId callId;
  final CallOfferId? offerId;
  final CallDirection direction;
  final CallPhase phase;
  final String remoteNumber;
  final String? customerId;
  final String? customerName;
  final String? ticketId;
  final String? ticketNumber;
  final String? category;
  final DateTime createdAt;
  final DateTime? answeredAt;

  factory ActiveCallSnapshot.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? value) =>
        DateTime.tryParse(value?.toString() ?? '')?.toUtc();
    final status = '${json['status'] ?? ''}'.toLowerCase();
    return ActiveCallSnapshot(
      callId: '${json['call_id'] ?? json['id'] ?? ''}',
      offerId: json['offer_id']?.toString(),
      direction: '${json['direction']}'.toLowerCase() == 'outbound'
          ? CallDirection.outbound
          : CallDirection.inbound,
      phase: status == 'held'
          ? CallPhase.held
          : status == 'ringing'
              ? CallPhase.incomingRinging
              : CallPhase.active,
      remoteNumber: '${json['caller_number'] ?? json['phone_number'] ?? ''}',
      customerId: json['customer_id']?.toString(),
      customerName: json['customer_name']?.toString(),
      ticketId: json['ticket_id']?.toString(),
      ticketNumber: json['ticket_number']?.toString(),
      category: json['category']?.toString(),
      createdAt: parseDate(json['created_at']) ?? DateTime.now().toUtc(),
      answeredAt: parseDate(json['answered_at'] ?? json['connected_at']),
    );
  }
}

class CallLogRecord {
  const CallLogRecord({
    required this.id,
    required this.direction,
    required this.status,
    required this.phoneNumber,
    required this.occurredAt,
    this.customerId,
    this.customerName,
    this.duration = Duration.zero,
    this.formattedDuration,
    this.ticketNumber,
    this.ticketSubject,
    this.agentName,
    this.transcript,
    this.recordingUrl,
  });

  final String id;
  final CallDirection direction;
  final CallLogStatus status;
  final String phoneNumber;
  final DateTime occurredAt;
  final String? customerId;
  final String? customerName;
  final Duration duration;
  final String? formattedDuration;
  final String? ticketNumber;
  final String? ticketSubject;
  final String? agentName;
  final String? transcript;
  final String? recordingUrl;

  bool get isAnswered =>
      status == CallLogStatus.completed && duration > Duration.zero;

  factory CallLogRecord.fromJson(Map<String, dynamic> json) {
    String? firstPresent(Iterable<Object?> values) {
      for (final value in values) {
        final text = value?.toString().trim();
        if (text != null && text.isNotEmpty && text.toLowerCase() != 'null') {
          return text;
        }
      }
      return null;
    }

    final rawStatus =
        '${json['status'] ?? json['call_status'] ?? ''}'.trim().toLowerCase();
    final rawDirection = '${json['direction'] ?? ''}'.trim().toLowerCase();
    final durationSeconds = int.tryParse(
          '${json['duration_seconds'] ?? json['duration'] ?? 0}',
        ) ??
        0;
    final timestamp = DateTime.tryParse(
          '${json['occurred_at'] ?? json['created_at'] ?? json['ended_at'] ?? ''}',
        )?.toLocal() ??
        DateTime.now();
    final direction = rawDirection == 'outbound'
        ? CallDirection.outbound
        : CallDirection.inbound;
    final nestedCustomer = json['customer'] is Map
        ? (json['customer'] as Map).map((key, value) => MapEntry('$key', value))
        : const <String, dynamic>{};
    final nestedTicket = json['ticket'] is Map
        ? (json['ticket'] as Map).map((key, value) => MapEntry('$key', value))
        : const <String, dynamic>{};
    final nestedTicketCustomer = nestedTicket['customer'] is Map
        ? (nestedTicket['customer'] as Map)
            .map((key, value) => MapEntry('$key', value))
        : const <String, dynamic>{};
    final resolvedName = firstPresent([
      json['caller_name'],
      json['customer_name'],
      nestedCustomer['name'],
      nestedTicketCustomer['name'],
    ]);
    final fromNumber = firstPresent([
          json['from_number'],
          json['caller_number'],
          json['remote_number'],
        ]) ??
        '';
    final toNumber = firstPresent([
          json['to_number'],
          json['phone_number'],
          json['remote_number'],
        ]) ??
        '';
    // The API resolves the actual customer phone independently of call
    // direction. Prefer it over the agent's device number in both inbound and
    // outbound entries; legacy responses fall back to the directional number.
    final customerPhone = firstPresent([
      json['customer_phone'],
      nestedCustomer['phone_number'],
      nestedCustomer['phone'],
      nestedTicketCustomer['phone_number'],
      nestedTicketCustomer['phone'],
    ]);
    final remoteNumber = customerPhone ??
        (direction == CallDirection.outbound ? toNumber : fromNumber);
    return CallLogRecord(
      id: '${json['call_id'] ?? json['id'] ?? ''}',
      direction: direction,
      status: switch (rawStatus) {
        'completed' || 'connected' || 'answered' => CallLogStatus.completed,
        'missed' || 'no_answer' => CallLogStatus.missed,
        'failed' || 'busy' => CallLogStatus.failed,
        'cancelled' || 'canceled' => CallLogStatus.cancelled,
        _ => CallLogStatus.unknown,
      },
      // For outbound calls the customer is the destination; for inbound
      // calls the customer is the originating number.
      phoneNumber: remoteNumber,
      occurredAt: timestamp,
      customerId: json['customer_id']?.toString() ??
          nestedCustomer['id']?.toString() ??
          nestedTicketCustomer['id']?.toString(),
      customerName: resolvedName,
      duration: Duration(seconds: durationSeconds.clamp(0, 31536000).toInt()),
      formattedDuration: firstPresent([json['formatted_duration']]),
      ticketNumber: firstPresent([
        json['ticket_number'],
        json['ticket_display_number'],
        nestedTicket['display_number'],
      ]),
      ticketSubject:
          firstPresent([nestedTicket['subject'], json['ticket_subject']]),
      agentName:
          firstPresent([json['agent_name'], (json['agent'] as Map?)?['name']]),
      transcript: firstPresent([json['transcript']]),
      recordingUrl: firstPresent([json['recording_url']]),
    );
  }
}

/// Result returned after the server has accepted an outbound originate request.
/// The provider session ID is useful for observability, but is deliberately
/// kept separate from [CallId]: lifecycle endpoints require the canonical call
/// ID when the backend eventually returns one.
class OutboundCallResult {
  const OutboundCallResult({
    required this.callSid,
    this.callId,
    this.sipUri,
    this.normalizedToNumber,
  });

  final String callSid;
  final CallId? callId;

  /// Backend-provided destination for the native SIP INVITE.
  final String? sipUri;
  final String? normalizedToNumber;

  factory OutboundCallResult.fromJson(Map<String, dynamic> json) {
    final callSid = '${json['call_sid'] ?? ''}'.trim();
    if (callSid.isEmpty) {
      throw const FormatException(
        'The call service did not return an outbound call session ID.',
      );
    }
    final callId = '${json['call_id'] ?? ''}'.trim();
    final sipUri = '${json['sip_uri'] ?? ''}'.trim();
    final normalized = '${json['normalized_to_number'] ?? ''}'.trim();
    return OutboundCallResult(
      callSid: callSid,
      callId: callId.isEmpty ? null : callId,
      sipUri: sipUri.isEmpty ? null : sipUri,
      normalizedToNumber: normalized.isEmpty ? null : normalized,
    );
  }
}

class CallLogPage {
  const CallLogPage({
    required this.records,
    required this.page,
    required this.hasMore,
  });

  final List<CallLogRecord> records;
  final int page;
  final bool hasMore;

  factory CallLogPage.fromJson(Object? value, {required int requestedPage}) {
    if (value is List) {
      return CallLogPage(
        records: value
            .whereType<Map>()
            .map((item) => CallLogRecord.fromJson(
                item.map((key, entry) => MapEntry('$key', entry))))
            .toList(growable: false),
        page: requestedPage,
        hasMore: false,
      );
    }
    if (value is! Map) {
      throw const FormatException(
        'The call history service returned an invalid response.',
      );
    }
    final map = value.map((key, entry) => MapEntry('$key', entry));
    final data = map['data'] is List
        ? map['data'] as List
        : map['calls'] is List
            ? map['calls'] as List
            : const <dynamic>[];
    final meta =
        map['meta'] is Map ? map['meta'] as Map : const <dynamic, dynamic>{};
    final page = int.tryParse(
            '${meta['current_page'] ?? map['current_page'] ?? requestedPage}') ??
        requestedPage;
    final lastPage =
        int.tryParse('${meta['last_page'] ?? map['last_page'] ?? page}') ??
            page;
    final records = data
        .whereType<Map>()
        .map((item) => CallLogRecord.fromJson(
            item.map((key, entry) => MapEntry('$key', entry))))
        .toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return CallLogPage(
      records: records,
      page: page,
      hasMore: page < lastPage,
    );
  }
}
