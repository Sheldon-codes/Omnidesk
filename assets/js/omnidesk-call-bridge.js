(function () {
  'use strict';

  var BRIDGE_VERSION = '2.0.0';
  var SDK_VERSION = '1.0.7';

  function emit(obj) {
    try {
      obj.v = 1;
      if (obj.sessionId == null) { obj.sessionId = activeSessionId; }
      if (obj.callSid == null && activeCallSid != null) {
        obj.callSid = activeCallSid;
      }
      if (obj.event) { lastEvent = obj.event; eventCount += 1; }
      OmniDeskBridge.postMessage(JSON.stringify(obj));
    } catch (e) { /* channel unavailable: Dart treats silence as failure */ }
  }

  function diagnostic(level, phase, details) {
    var safe = {};
    details = details || {};
    // Explicit allowlist: never forward tokens, SDP, ICE credentials,
    // destinations, arbitrary SDK errors, or media payloads to native logs.
    [
      'secureContext', 'visibility', 'hidden', 'focused', 'origin',
      'shellVersion', 'sdkVersion', 'hasMediaDevices', 'hasGetUserMedia',
      'hasPeerConnection', 'eventName', 'required', 'errorName',
      'audioTrackCount', 'trackState', 'trackEnabled', 'trackMuted',
      'signalingState', 'iceGatheringState', 'iceConnectionState',
      'connectionState', 'providerEventCount'
    ].forEach(function (key) {
      if (details[key] !== undefined && details[key] !== null) {
        safe[key] = details[key];
      }
    });
    emit({
      event: 'diagnostic',
      level: level || 'info',
      phase: phase,
      timestamp: Date.now(),
      details: safe
    });
    try { console.log('[OmniDeskBridge][' + phase + '] ' + JSON.stringify(safe)); } catch (_) {}
  }

  // Async failures inside client.call() (rejected media promises, SDP
  // errors) bypass the try/catch around the call site. Surface them —
  // otherwise a dead dial looks identical to a slow one.
  window.addEventListener('error', function (event) {
    diagnostic('error', 'window_error', {
      errorName: (event && event.error && event.error.name) || 'Error'
    });
    try {
      console.log(
        '[bridge] window.error: ' + (event.message || 'unknown') +
        ' @' + (event.filename || '?') + ':' + (event.lineno || '?')
      );
    } catch (e) {}
  });
  window.addEventListener('unhandledrejection', function (event) {
    diagnostic('error', 'unhandled_rejection', {
      errorName: event && event.reason && event.reason.name || 'PromiseRejection'
    });
    try {
      var reason = event.reason;
      var text = (reason && (reason.name || reason.message))
        ? ((reason.name || '') + ': ' + (reason.message || ''))
        : String(reason);
      console.log('[bridge] unhandledrejection: ' + text);
    } catch (e) {}
  });

  var client = null;
  var pendingIncoming = null;
  var heartbeatTimer = null;
  var activeSessionId = null;
  var activeCallSid = null;
  var lastEvent = 'page_ready';
  var eventCount = 0;
  var providerEventCount = 0;
  var clientReady = false;

  function documentDetails() {
    return {
      secureContext: window.isSecureContext,
      visibility: document.visibilityState,
      hidden: !!document.hidden,
      focused: typeof document.hasFocus === 'function' && document.hasFocus(),
      origin: location.origin,
      shellVersion: document.documentElement.getAttribute('data-omnidesk-shell') || 'legacy',
      sdkVersion: SDK_VERSION,
      hasMediaDevices: !!navigator.mediaDevices,
      hasGetUserMedia: !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia),
      hasPeerConnection: typeof window.RTCPeerConnection === 'function'
    };
  }

  function startHeartbeat(callSid) {
    stopHeartbeat();
    heartbeatTimer = setInterval(function () {
      emit({ event: 'heartbeat', callSid: callSid || null });
    }, 5000);
  }

  function stopHeartbeat() {
    if (heartbeatTimer) { clearInterval(heartbeatTimer); heartbeatTimer = null; }
  }

  function bindClientEvent(name, required, handler) {
    try {
      diagnostic('debug', 'client_event_binding_started', {
        eventName: name, required: required
      });
      client.on(name, function (params) {
        providerEventCount += 1;
        diagnostic('info', 'provider_event_received', {
          eventName: name, providerEventCount: providerEventCount
        });
        handler(params);
      });
      return true;
    } catch (error) {
      diagnostic(required ? 'error' : 'warning', 'client_event_binding_failed', {
        eventName: name,
        required: required,
        errorName: error && error.name || 'Error'
      });
      return !required;
    }
  }

  function bindClientEvents() {
    // Mirrors the browser softphone subscription set: ready, incomingcall,
    // calling/outbound progress, callaccepted, hangup, offline/error.
    diagnostic('info', 'client_event_binding_started', documentDetails());
    var requiredBindingsOk = true;
    requiredBindingsOk = bindClientEvent('ready', true, function () {
      clientReady = true;
      diagnostic('info', 'at_ready', documentDetails());
      emit({ event: 'ready' });
    }) && requiredBindingsOk;
    requiredBindingsOk = bindClientEvent('incomingcall', true, function (params) {
      params = params || {};
      pendingIncoming = params;
      diagnostic('info', 'incoming_received', documentDetails());
      emit({
        event: 'incoming',
        from: params.from || params.callerNumber || null,
        sessionId: params.sessionId || params.callSessionId || null,
      });
    }) && requiredBindingsOk;
    requiredBindingsOk = bindClientEvent('calling', true, function (params) {
      emit({ event: 'ringing', callSid: (params && params.callSid) || null });
    }) && requiredBindingsOk;
    requiredBindingsOk = bindClientEvent('callaccepted', true, function (params) {
      diagnostic('info', 'connected', documentDetails());
      emit({ event: 'connected', callSid: (params && params.callSid) || null });
    }) && requiredBindingsOk;
    requiredBindingsOk = bindClientEvent('hangup', true, function (params) {
      stopHeartbeat();
      pendingIncoming = null;
      diagnostic('info', 'hangup', documentDetails());
      emit({
        event: 'ended',
        callSid: (params && params.callSid) || null,
        reason: (params && (params.code || params.reason)) || null,
      });
    }) && requiredBindingsOk;
    bindClientEvent('missedcall', false, function (params) {
      stopHeartbeat();
      pendingIncoming = null;
      emit({
        event: 'ended',
        callSid: (params && params.callSid) || null,
        reason: 'missed',
      });
    });
    requiredBindingsOk = bindClientEvent('offline', true, function () {
      clientReady = false;
      diagnostic('error', 'at_offline', documentDetails());
      emit({ event: 'error', reason: 'token_expired' });
    }) && requiredBindingsOk;
    requiredBindingsOk = bindClientEvent('error', true, function (err) {
      diagnostic('error', 'at_error', {
        errorName: err && err.name || 'ProviderError'
      });
      emit({ event: 'error', reason: (err && (err.message || err.cause)) || 'client_error' });
    }) && requiredBindingsOk;
    bindClientEvent('disconnect', false, function () {
      clientReady = false;
      diagnostic('error', 'at_disconnect', documentDetails());
      emit({ event: 'error', reason: 'client_disconnected' });
    });
    bindClientEvent('closed', false, function () {
      clientReady = false;
      diagnostic('error', 'at_closed', documentDetails());
      emit({ event: 'ended', reason: 'connection_closed' });
    });
    requiredBindingsOk = bindClientEvent('notready', true, function () {
      clientReady = false;
      diagnostic('error', 'at_notready', documentDetails());
      emit({ event: 'ended', reason: 'media_unregistered' });
    }) && requiredBindingsOk;
    diagnostic(requiredBindingsOk ? 'info' : 'error', 'client_event_binding_completed', {
      required: requiredBindingsOk,
      providerEventCount: providerEventCount
    });
    return requiredBindingsOk;
  }

  window.OmniDesk = window.OmniDesk || {};
  // The AT client gates its gateway connection on legacy
  // `navigator.getUserMedia`, which modern WebKit no longer provides
  // (only `navigator.mediaDevices.getUserMedia` remains). Without this
  // shim its support check fails silently and no connection is attempted.
  if (typeof navigator.getUserMedia === 'undefined' &&
      navigator.mediaDevices &&
      typeof navigator.mediaDevices.getUserMedia === 'function') {
    navigator.getUserMedia = function (constraints, success, failure) {
      diagnostic('info', 'get_user_media_started', documentDetails());
      navigator.mediaDevices.getUserMedia(constraints).then(
        function (stream) {
          var tracks = stream.getAudioTracks ? stream.getAudioTracks() : [];
          var track = tracks[0];
          diagnostic('info', 'get_user_media_resolved', {
            audioTrackCount: tracks.length,
            trackState: track && track.readyState,
            trackEnabled: track && track.enabled,
            trackMuted: track && track.muted
          });
          emit({ event: 'mic', mic: 'granted', detail: 'SDK capture granted' });
          if (typeof success === 'function') { success(stream); }
        },
        function (error) {
          diagnostic('error', 'get_user_media_rejected', {
            errorName: error && error.name || 'MediaError'
          });
          var detail = (error && (error.name + ': ' + error.message)) || 'SDK capture rejected';
          emit({ event: 'error', reason: 'microphone: ' + detail });
          if (typeof failure === 'function') { failure(error); }
        }
      );
    };
  }
  window.OmniDesk.call = {
    init: function (args) {
      args = args || {};
      activeSessionId = args.sessionId || null;
      activeCallSid = args.callSid || null;
      providerEventCount = 0;
      clientReady = false;
      diagnostic('info', 'client_init_received', documentDetails());
      if (typeof window.Africastalking === 'undefined') {
        emit({ event: 'error', reason: 'at_client_missing' });
        return;
      }
      // NOTE: africastalking-client@1.0.7 hardcodes its gateway to
      // wss://webrtc.africastalking.com/connect. The constructor only
      // accepts {iceServers, sounds}; there is no gatewayUrl or server
      // option. Any backend-provided gateway URL (e.g. :4443 — TCP-dead per
      // device nc test) cannot be forwarded to the SDK.
      try {
        if (client && typeof client.hangup === 'function') {
          try { client.hangup(); } catch (e) {}
        }
        // Pass sounds:{} to suppress the SDK's CDN-hosted ringtone/dialing
        // MP3s. Flutter owns all audio feedback; letting the SDK fetch and
        // play sounds from a headless WebView produces ghost audio.
        diagnostic('info', 'client_constructor_started', documentDetails());
        client = new window.Africastalking.Client(args.token, { sounds: {} });
        diagnostic('info', 'client_constructor_returned', documentDetails());
        if (!bindClientEvents()) {
          emit({ event: 'error', reason: 'required_event_binding_failed' });
          return;
        }
        startHeartbeat(args.callSid);
        diagnostic('info', 'client_ready_wait_started', documentDetails());
        // 'ready' arrives via the client event above once media connects.
      } catch (e) {
        emit({ event: 'error', reason: (e && e.message) || 'init_failed' });
      }
    },
    dial: function (phoneNumber, callSid) {
      activeCallSid = callSid || null;
      if (!client || typeof client.call !== 'function') {
        emit({ event: 'error', callSid: callSid || null, reason: 'not_initialized' });
        return;
      }
      try {
        diagnostic('info', 'dial_requested', documentDetails());
        startHeartbeat(callSid);
        client.call(phoneNumber);
      } catch (e) {
        emit({ event: 'error', callSid: callSid || null, reason: (e && e.message) || 'dial_failed' });
      }
    },
    prepareSession: function (sessionId, callSid) {
      activeSessionId = sessionId || null;
      activeCallSid = callSid || null;
      return clientReady ? 'ready' : 'notready';
    },
    answer: function (callSid) {
      activeCallSid = callSid || activeCallSid;
      if (!client || typeof client.answer !== 'function') {
        emit({ event: 'error', callSid: callSid || null, reason: 'not_initialized' });
        return;
      }
      try {
        diagnostic('info', 'answer_requested', documentDetails());
        startHeartbeat(callSid);
        client.answer();
        pendingIncoming = null;
      } catch (e) {
        emit({ event: 'error', callSid: callSid || null, reason: (e && e.message) || 'answer_failed' });
      }
    },
    hangup: function () {
      diagnostic('info', 'cleanup_started', documentDetails());
      try {
        if (client && typeof client.hangup === 'function') client.hangup();
      } catch (e) {}
      stopHeartbeat();
      pendingIncoming = null;
      activeCallSid = null;
      diagnostic('info', 'cleanup_completed', documentDetails());
    },
    mute: function (enabled) {
      try {
        if (!client) return 'not_initialized';
        if (enabled && typeof client.muteAudio === 'function') {
          client.muteAudio(); return 'ok';
        }
        if (!enabled && typeof client.unmuteAudio === 'function') {
          client.unmuteAudio(); return 'ok';
        }
        return 'unsupported';
      } catch (e) { return 'failed'; }
    },
    hold: function (enabled) {
      try {
        if (!client) return 'not_initialized';
        if (enabled && typeof client.hold === 'function') {
          client.hold(); return 'ok';
        }
        if (!enabled && typeof client.unhold === 'function') {
          client.unhold(); return 'ok';
        }
        return 'unsupported';
      } catch (e) { return 'failed'; }
    },
    dtmf: function (digit) {
      try {
        if (!client) return 'not_initialized';
        if (typeof client.dtmf !== 'function') return 'unsupported';
        client.dtmf(digit); return 'ok';
      } catch (e) { return 'failed'; }
    },
    // Probes microphone capture without keeping the stream: the AT client's
    // createOffer fails silently (no-op logger) when capture is unavailable,
    // so Dart checks this explicitly instead of waiting out a dead dial.
    // The verdict arrives as a mic event; the return value is meaningless
    // because JS promises do not cross the native bridge.
    micCheck: function () {
      function report(mic, detail) {
        emit({ event: 'mic', mic: mic, detail: detail });
      }
      try {
        console.log('[Bridge] micCheck start: isSecureContext=' + window.isSecureContext + ' origin=' + location.origin + ' href=' + location.href);
        if (!(navigator.mediaDevices && typeof navigator.mediaDevices.getUserMedia === 'function')) {
          report('unavailable', 'mediaDevices.getUserMedia missing (secure=' + window.isSecureContext + ')');
          return;
        }
        navigator.mediaDevices.getUserMedia({ audio: true }).then(
          function (stream) {
            var audioTracks = stream.getAudioTracks ? stream.getAudioTracks() : [];
            var count = audioTracks.length;
            var state = (count > 0 && audioTracks[0].readyState) || 'unknown';
            console.log('[Bridge] getUserMedia success: tracks=' + count + ' state=' + state);
            try {
              stream.getTracks().forEach(function (t) { t.stop(); });
            } catch (e) {}
            if (count > 0) {
              report('granted', 'tracks=' + count + ' state=' + state + ' secure=' + window.isSecureContext);
            } else {
              report('unavailable', 'zero audio tracks returned');
            }
          },
          function (err) {
            console.error('[Bridge] getUserMedia error: ' + (err && (err.name + ': ' + err.message)));
            report('denied', (err && (err.name + ': ' + err.message)) || 'getUserMedia rejected');
          }
        );
      } catch (e) {
        console.error('[Bridge] micCheck threw: ' + (e && e.message));
        report('unavailable', (e && e.message) || 'probe threw');
      }
    },
    status: function () {
      var md = navigator.mediaDevices;
      return {
        bridge: true,
        atLib: typeof window.Africastalking,
        hasClient: !!client,
        clientReady: clientReady,
        lastEvent: lastEvent,
        eventCount: eventCount,
        providerEventCount: providerEventCount,
        bridgeVersion: BRIDGE_VERSION,
        sdkVersion: SDK_VERSION,
        visibility: document.visibilityState,
        hidden: !!document.hidden,
        focused: typeof document.hasFocus === 'function' && document.hasFocus(),
        // Replicates the AT client's own gate: RTCPeerConnection plus
        // LEGACY navigator.getUserMedia (not mediaDevices.*). When false the
        // client never opens its gateway socket and emits nothing.
        rtcPeerConnection: typeof window.RTCPeerConnection,
        legacyGetUserMedia: typeof navigator.getUserMedia,
        mediaDevicesGUM: typeof (md && md.getUserMedia),
        isSecureContext: window.isSecureContext,
        origin: location.origin,
        href: location.href,
      };
    },
  };

  // Signal page liveness so Dart can distinguish "bridge loaded" from silence.
  diagnostic('info', 'document_loaded', documentDetails());
  emit({ event: 'page_ready' });
})();
