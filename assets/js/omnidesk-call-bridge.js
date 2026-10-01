(function () {
  'use strict';

  // The AT SDK owns browser media semantics. This bridge never replaces
  // RTCPeerConnection, peer methods, mediaDevices.getUserMedia, or play().
  var BRIDGE_VERSION = '2.1.0';
  var SDK_VERSION = '1.0.7';
  var client = null;
  var pendingIncoming = null;
  var heartbeatTimer = null;
  var activeSessionId = null;
  var activeCallSid = null;
  var lastEvent = 'page_ready';
  var eventCount = 0;
  var providerEventCount = 0;
  var clientReady = false;
  var debugInspectorEnabled = false;
  var inspector = null;
  var inspectorStatus = null;
  var inspectorTimer = null;
  var nativeAudioSession = null;
  var observedAudioElements = [];

  function emit(obj) {
    try {
      obj.v = 1;
      if (obj.sessionId == null) { obj.sessionId = activeSessionId; }
      if (obj.callSid == null && activeCallSid != null) { obj.callSid = activeCallSid; }
      if (obj.event) { lastEvent = obj.event; eventCount += 1; }
      OmniDeskBridge.postMessage(JSON.stringify(obj));
    } catch (_) { /* Dart treats bridge silence as a bounded setup failure. */ }
  }

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

  function diagnostic(level, phase, details) {
    var safe = {};
    details = details || {};
    [
      'secureContext', 'visibility', 'hidden', 'focused', 'origin',
      'shellVersion', 'sdkVersion', 'hasMediaDevices', 'hasGetUserMedia',
      'hasPeerConnection', 'eventName', 'required', 'errorName',
      'audioTrackCount', 'trackState', 'trackEnabled', 'trackMuted',
      'providerEventCount', 'returnType', 'promiseState',
      'audioElementCount', 'mediaElementState', 'audioOutputMuted',
      'audioOutputVolume', 'audioOutputPaused'
    ].forEach(function (key) {
      if (details[key] !== undefined && details[key] !== null) { safe[key] = details[key]; }
    });
    emit({ event: 'diagnostic', level: level || 'info', phase: phase, timestamp: Date.now(), details: safe });
    updateInspector();
    try { console.log('[OmniDeskBridge][' + phase + '] ' + JSON.stringify(safe)); } catch (_) {}
  }

  function startHeartbeat(callSid) {
    stopHeartbeat();
    heartbeatTimer = setInterval(function () { emit({ event: 'heartbeat', callSid: callSid || null }); }, 5000);
  }

  function stopHeartbeat() {
    if (heartbeatTimer) { clearInterval(heartbeatTimer); heartbeatTimer = null; }
  }

  function retainIdleHeartbeat() {
    if (clientReady) { startHeartbeat(null); } else { stopHeartbeat(); }
  }

  function audioDetails(element) {
    return {
      audioElementCount: observedAudioElements.length,
      mediaElementState: element.readyState,
      audioOutputMuted: element.muted,
      audioOutputVolume: element.volume,
      audioOutputPaused: element.paused
    };
  }

  // Observing an AT-owned element is safe. Never call play(), set srcObject,
  // or alter muted/volume state from diagnostic code.
  function observeAudioElement(element) {
    if (!element || element.tagName !== 'AUDIO' || observedAudioElements.indexOf(element) !== -1) { return; }
    observedAudioElements.push(element);
    diagnostic('info', 'remote_audio_element_created', audioDetails(element));
    ['loadedmetadata', 'canplay', 'playing', 'pause', 'waiting', 'ended'].forEach(function (eventName) {
      element.addEventListener(eventName, function () { diagnostic('info', 'remote_audio_' + eventName, audioDetails(element)); });
    });
    element.addEventListener('error', function () { diagnostic('error', 'remote_audio_error', { errorName: 'MediaElementError' }); });
  }

  function observeAudioElements() {
    if (!document.querySelectorAll) { return; }
    var elements = document.querySelectorAll('audio');
    for (var index = 0; index < elements.length; index += 1) { observeAudioElement(elements[index]); }
  }

  function installPassiveAudioObserver() {
    if (typeof MutationObserver !== 'function' || !document.documentElement) { return; }
    new MutationObserver(observeAudioElements).observe(document.documentElement, { childList: true, subtree: true });
    observeAudioElements();
  }

  function inspectorText() {
    var details = documentDetails();
    var lines = [
      'OmniDesk Call Engine — iOS debug experiment',
      'bridge=' + BRIDGE_VERSION + ' sdk=' + SDK_VERSION,
      'secure=' + details.secureContext + ' visibility=' + details.visibility + ' focused=' + details.focused,
      'AT ready=' + clientReady + ' providerEvents=' + providerEventCount,
      'last=' + lastEvent + ' pageEvents=' + eventCount,
      'audioElements=' + observedAudioElements.length
    ];
    if (nativeAudioSession) {
      lines.push('CallKit phase=' + nativeAudioSession.phase + ' route=' + nativeAudioSession.route + ' input=' + nativeAudioSession.inputAvailable + ' speaker=' + nativeAudioSession.speakerRequested);
    }
    if (observedAudioElements[0]) {
      var audio = audioDetails(observedAudioElements[0]);
      lines.push('audio paused=' + audio.audioOutputPaused + ' readyState=' + audio.mediaElementState + ' muted=' + audio.audioOutputMuted);
    }
    lines.push('Peer/RTP details are intentionally unavailable: this bridge does not instrument browser media APIs.');
    return lines.join('\n');
  }

  function updateInspector() {
    if (inspectorStatus) { inspectorStatus.textContent = inspectorText(); }
  }

  function setDebugInspector(enabled) {
    debugInspectorEnabled = !!enabled;
    if (!debugInspectorEnabled) {
      if (inspectorTimer) { clearInterval(inspectorTimer); inspectorTimer = null; }
      if (inspector && inspector.parentNode) { inspector.parentNode.removeChild(inspector); }
      inspector = null;
      inspectorStatus = null;
      document.documentElement.style.background = 'transparent';
      if (document.body) { document.body.style.background = 'transparent'; document.body.style.pointerEvents = 'none'; }
      return 'ok';
    }
    if (!document.body) { return 'notready'; }
    document.body.removeAttribute('aria-hidden');
    document.documentElement.style.background = '#101216';
    document.body.style.background = '#101216';
    document.body.style.pointerEvents = 'auto';
    document.body.style.margin = '0';
    document.body.style.fontFamily = '-apple-system, BlinkMacSystemFont, sans-serif';
    if (!inspector) {
      inspector = document.createElement('main');
      inspector.style.cssText = 'box-sizing:border-box;min-height:100vh;padding:52px 24px 32px;background:#101216;color:#f5f7fa;display:flex;flex-direction:column;gap:22px;';
      var title = document.createElement('h1');
      title.textContent = 'Call media diagnostic';
      title.style.cssText = 'font-size:26px;line-height:1.2;margin:0;';
      var note = document.createElement('p');
      note.textContent = 'Debug build only. This page does not answer, hang up, or alter media.';
      note.style.cssText = 'margin:0;color:#b7beca;line-height:1.45;';
      var activate = document.createElement('button');
      activate.type = 'button';
      activate.textContent = 'Activate call engine';
      activate.style.cssText = 'min-height:52px;border:0;border-radius:12px;background:#f43f8f;color:#fff;font-size:17px;font-weight:700;';
      activate.addEventListener('click', function () {
        try { window.focus(); document.body.focus(); } catch (_) {}
        diagnostic('info', 'debug_inspector_activated', documentDetails());
      });
      inspectorStatus = document.createElement('pre');
      inspectorStatus.style.cssText = 'white-space:pre-wrap;overflow-wrap:anywhere;margin:0;padding:16px;border-radius:12px;background:#1b1f27;color:#dce3ee;font-size:13px;line-height:1.55;';
      inspector.appendChild(title);
      inspector.appendChild(note);
      inspector.appendChild(activate);
      inspector.appendChild(inspectorStatus);
      document.body.appendChild(inspector);
    }
    updateInspector();
    if (!inspectorTimer) { inspectorTimer = setInterval(updateInspector, 500); }
    diagnostic('info', 'debug_inspector_visible', documentDetails());
    return 'ok';
  }

  function setNativeAudioSession(snapshot) {
    snapshot = snapshot || {};
    nativeAudioSession = {
      phase: String(snapshot.phase || 'unknown'),
      category: String(snapshot.category || 'unknown'),
      mode: String(snapshot.mode || 'unknown'),
      route: String(snapshot.route || 'unknown'),
      inputAvailable: snapshot.inputAvailable === true,
      speakerRequested: snapshot.speakerRequested === true
    };
    updateInspector();
    return 'ok';
  }

  function bindClientEvent(name, required, handler) {
    try {
      diagnostic('debug', 'client_event_binding_started', { eventName: name, required: required });
      client.on(name, function (params) {
        providerEventCount += 1;
        diagnostic('info', 'provider_event_received', { eventName: name, providerEventCount: providerEventCount });
        handler(params || {});
      });
      return true;
    } catch (error) {
      diagnostic(required ? 'error' : 'warning', 'client_event_binding_failed', { eventName: name, required: required, errorName: error && error.name || 'Error' });
      return !required;
    }
  }

  function bindClientEvents() {
    var requiredBindingsOk = true;
    requiredBindingsOk = bindClientEvent('ready', true, function () { clientReady = true; diagnostic('info', 'at_ready', documentDetails()); emit({ event: 'ready' }); }) && requiredBindingsOk;
    requiredBindingsOk = bindClientEvent('incomingcall', true, function (params) { pendingIncoming = params; diagnostic('info', 'incoming_received', documentDetails()); emit({ event: 'incoming' }); }) && requiredBindingsOk;
    requiredBindingsOk = bindClientEvent('calling', true, function (params) { emit({ event: 'ringing', callSid: params.callSid || null }); }) && requiredBindingsOk;
    requiredBindingsOk = bindClientEvent('callaccepted', true, function (params) { diagnostic('info', 'connected', documentDetails()); emit({ event: 'connected', callSid: params.callSid || null }); }) && requiredBindingsOk;
    requiredBindingsOk = bindClientEvent('hangup', true, function (params) { pendingIncoming = null; retainIdleHeartbeat(); diagnostic('info', 'hangup', documentDetails()); emit({ event: 'ended', callSid: params.callSid || null, reason: params.code || params.reason || null }); }) && requiredBindingsOk;
    bindClientEvent('missedcall', false, function (params) { pendingIncoming = null; retainIdleHeartbeat(); emit({ event: 'ended', callSid: params.callSid || null, reason: 'missed' }); });
    requiredBindingsOk = bindClientEvent('offline', true, function () { clientReady = false; diagnostic('error', 'at_offline', documentDetails()); emit({ event: 'error', reason: 'token_expired' }); }) && requiredBindingsOk;
    requiredBindingsOk = bindClientEvent('error', true, function (error) { diagnostic('error', 'at_error', { errorName: error && error.name || 'ProviderError' }); emit({ event: 'error', reason: (error && (error.message || error.cause)) || 'client_error' }); }) && requiredBindingsOk;
    bindClientEvent('disconnect', false, function () { clientReady = false; diagnostic('error', 'at_disconnect', documentDetails()); emit({ event: 'error', reason: 'client_disconnected' }); });
    bindClientEvent('closed', false, function () { clientReady = false; diagnostic('error', 'at_closed', documentDetails()); emit({ event: 'ended', reason: 'connection_closed' }); });
    requiredBindingsOk = bindClientEvent('notready', true, function () { clientReady = false; diagnostic('error', 'at_notready', documentDetails()); emit({ event: 'ended', reason: 'media_unregistered' }); }) && requiredBindingsOk;
    diagnostic(requiredBindingsOk ? 'info' : 'error', 'client_event_binding_completed', { required: requiredBindingsOk, providerEventCount: providerEventCount });
    return requiredBindingsOk;
  }

  // AT 1.0.7 checks the legacy callback API. Modern WebKit exposes only the
  // standards Promise API, so add the legacy name only when it is absent.
  if (typeof navigator.getUserMedia !== 'function' && navigator.mediaDevices && typeof navigator.mediaDevices.getUserMedia === 'function') {
    navigator.getUserMedia = function (constraints, success, failure) {
      diagnostic('info', 'get_user_media_started', documentDetails());
      var request = navigator.mediaDevices.getUserMedia(constraints);
      request.then(function (stream) {
        var tracks = stream && stream.getAudioTracks ? stream.getAudioTracks() : [];
        var track = tracks[0];
        diagnostic('info', 'get_user_media_resolved', { audioTrackCount: tracks.length, trackState: track && track.readyState, trackEnabled: track && track.enabled, trackMuted: track && track.muted });
        emit({ event: 'mic', mic: 'granted', detail: 'SDK capture granted' });
        if (typeof success === 'function') { success(stream); }
      }, function (error) {
        diagnostic('error', 'get_user_media_rejected', { errorName: error && error.name || 'MediaError' });
        if (typeof failure === 'function') { failure(error); }
      });
      return request;
    };
  }

  window.OmniDesk = window.OmniDesk || {};
  window.OmniDesk.call = {
    init: function (args) {
      args = args || {};
      activeSessionId = args.sessionId || null;
      activeCallSid = args.callSid || null;
      providerEventCount = 0;
      clientReady = false;
      diagnostic('info', 'client_init_received', documentDetails());
      if (typeof window.Africastalking === 'undefined') { emit({ event: 'error', reason: 'at_client_missing' }); return; }
      try {
        if (client && typeof client.hangup === 'function') { try { client.hangup(); } catch (_) {} }
        diagnostic('info', 'client_constructor_started', documentDetails());
        client = new window.Africastalking.Client(args.token, { sounds: {} });
        diagnostic('info', 'client_constructor_returned', documentDetails());
        if (!bindClientEvents()) { emit({ event: 'error', reason: 'required_event_binding_failed' }); return; }
        startHeartbeat(args.callSid);
        diagnostic('info', 'client_ready_wait_started', documentDetails());
      } catch (error) { emit({ event: 'error', reason: (error && error.message) || 'init_failed' }); }
    },
    dial: function (phoneNumber, callSid) {
      activeCallSid = callSid || null;
      if (!client || typeof client.call !== 'function') { emit({ event: 'error', callSid: callSid || null, reason: 'not_initialized' }); return; }
      try {
        diagnostic('info', 'dial_requested', documentDetails());
        startHeartbeat(callSid);
        var result = client.call(phoneNumber);
        diagnostic('info', 'dial_invoked', { returnType: typeof result, providerEventCount: providerEventCount });
        if (result && typeof result.then === 'function') {
          result.then(function () { diagnostic('info', 'dial_promise_resolved', { promiseState: 'resolved', providerEventCount: providerEventCount }); }, function (error) {
            diagnostic('error', 'dial_promise_rejected', { promiseState: 'rejected', errorName: error && error.name || 'ProviderError' });
            emit({ event: 'error', callSid: callSid || null, reason: (error && error.message) || 'dial_rejected' });
          });
        }
      } catch (error) { emit({ event: 'error', callSid: callSid || null, reason: (error && error.message) || 'dial_failed' }); }
    },
    prepareSession: function (sessionId, callSid) { activeSessionId = sessionId || null; activeCallSid = callSid || null; return clientReady ? 'ready' : 'notready'; },
    answer: function (callSid) {
      activeCallSid = callSid || activeCallSid;
      if (!client || typeof client.answer !== 'function') { emit({ event: 'error', callSid: callSid || null, reason: 'not_initialized' }); return; }
      try { diagnostic('info', 'answer_requested', documentDetails()); startHeartbeat(callSid); client.answer(); pendingIncoming = null; } catch (error) { emit({ event: 'error', callSid: callSid || null, reason: (error && error.message) || 'answer_failed' }); }
    },
    hangup: function () { diagnostic('info', 'cleanup_started', documentDetails()); try { if (client && typeof client.hangup === 'function') { client.hangup(); } } catch (_) {} pendingIncoming = null; activeCallSid = null; retainIdleHeartbeat(); diagnostic('info', 'cleanup_completed', documentDetails()); },
    mute: function (enabled) { try { if (!client) return 'not_initialized'; if (enabled && typeof client.muteAudio === 'function') { client.muteAudio(); return 'ok'; } if (!enabled && typeof client.unmuteAudio === 'function') { client.unmuteAudio(); return 'ok'; } return 'unsupported'; } catch (_) { return 'failed'; } },
    hold: function (enabled) { try { if (!client) return 'not_initialized'; if (enabled && typeof client.hold === 'function') { client.hold(); return 'ok'; } if (!enabled && typeof client.unhold === 'function') { client.unhold(); return 'ok'; } return 'unsupported'; } catch (_) { return 'failed'; } },
    dtmf: function (digit) { try { if (!client) return 'not_initialized'; if (typeof client.dtmf !== 'function') return 'unsupported'; client.dtmf(digit); return 'ok'; } catch (_) { return 'failed'; } },
    setDebugInspector: setDebugInspector,
    setNativeAudioSession: setNativeAudioSession,
    status: function () {
      var details = documentDetails();
      return { bridge: true, atLib: typeof window.Africastalking, hasClient: !!client, clientReady: clientReady, callAttached: pendingIncoming !== null || activeCallSid !== null, lastEvent: lastEvent, eventCount: eventCount, providerEventCount: providerEventCount, bridgeVersion: BRIDGE_VERSION, sdkVersion: SDK_VERSION, visibility: details.visibility, hidden: details.hidden, focused: details.focused, rtcPeerConnection: typeof window.RTCPeerConnection, legacyGetUserMedia: typeof navigator.getUserMedia, mediaDevicesGUM: typeof (navigator.mediaDevices && navigator.mediaDevices.getUserMedia), isSecureContext: window.isSecureContext, origin: location.origin, debugInspectorEnabled: debugInspectorEnabled };
    }
  };

  installPassiveAudioObserver();
  window.addEventListener('error', function (event) { diagnostic('error', 'window_error', { errorName: event && event.error && event.error.name || 'Error' }); });
  window.addEventListener('unhandledrejection', function (event) { diagnostic('error', 'unhandled_rejection', { errorName: event && event.reason && event.reason.name || 'PromiseRejection' }); });
  diagnostic('info', 'document_loaded', documentDetails());
  emit({ event: 'page_ready' });
})();
