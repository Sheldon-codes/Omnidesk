#import "OmniDeskBaresipAdapter.h"

#import <AVFoundation/AVFoundation.h>
#import <os/log.h>
#import <pthread.h>
#import <string.h>
#import "re.h"
#import "baresip.h"

static NSString * const OmniDeskBaresipErrorDomain = @"com.bigbrainzsolutions.omnidesk.baresip";
static os_log_t OmniDeskBaresipLog(void) {
  return os_log_create("com.bigbrainzsolutions.omnidesk", "NativeCallMedia");
}

static void *omni_baresip_loop(void *unused) {
  (void)unused;
  re_main(NULL);
  return NULL;
}

@interface OmniDeskBaresipAdapter () {
  struct ua *_ua;
  struct call *_call;
  BOOL _started;
  NSString *_mediaSessionId;
  NSString *_callId;
  NSString *_callSid;
  dispatch_queue_t _queue;
}
@property(nonatomic, copy) OmniDeskBaresipEventHandler handler;
- (void)handleEvent:(enum ua_event)event
               call:(struct call *)call
             reason:(NSString *)reason;
/// Points OpenSSL at bundled root CAs. iOS ships no default verify paths,
/// so without this every SIP/TLS handshake fails certificate validation.
- (void)configureTlsTrust;
@end

static void omni_ua_event(struct ua *ua, enum ua_event event, struct call *call,
                          const char *prm, void *arg) {
  (void)ua;
  OmniDeskBaresipAdapter *adapter = (__bridge OmniDeskBaresipAdapter *)arg;
  NSString *reason = prm ? [NSString stringWithUTF8String:prm] : nil;
  [adapter handleEvent:event call:call reason:reason];
}

@implementation OmniDeskBaresipAdapter

- (NSString *)mediaSessionId { return _mediaSessionId; }
- (NSString *)callId { return _callId; }
- (NSString *)callSid { return _callSid; }

- (instancetype)initWithEventHandler:(OmniDeskBaresipEventHandler)handler {
  self = [super init];
  if (self) {
    _handler = [handler copy];
    _queue = dispatch_queue_create("com.bigbrainzsolutions.omnidesk.baresip", DISPATCH_QUEUE_SERIAL);
  }
  return self;
}

- (NSError *)error:(NSString *)message code:(NSInteger)code {
  return [NSError errorWithDomain:OmniDeskBaresipErrorDomain
                              code:code
                          userInfo:@{NSLocalizedDescriptionKey: message}];
}

- (NSString *)sipUri:(NSString *)value transport:(NSString *)transport {
  NSString *normalized = value;
  if (![normalized.lowercaseString hasPrefix:@"sip:"] &&
      ![normalized.lowercaseString hasPrefix:@"sips:"]) {
    normalized = [@"sip:" stringByAppendingString:normalized];
  }
  // Baresip selects the SIP socket from the account/route URI. The API
  // transport field is authoritative; without this parameter it attempts an
  // unavailable default transport and returns ENOSYS before any TLS traffic.
  if (transport.length > 0 &&
      [normalized rangeOfString:@";transport=" options:NSCaseInsensitiveSearch].location == NSNotFound) {
    normalized = [normalized stringByAppendingFormat:@";transport=%@", transport.lowercaseString];
  }
  return normalized;
}

- (BOOL)startEngine:(NSError **)error {
  if (_started) return YES;
  os_log_info(OmniDeskBaresipLog(), "Initializing Baresip media engine");
  int result = libre_init();
  if (result) {
    os_log_error(OmniDeskBaresipLog(), "libre_init failed: %d", result);
    if (error) *error = [self error:@"Libre initialization failed." code:result];
    return NO;
  }
  static const uint8_t config[] =
      "sip_listen 0.0.0.0:0\n"
      "audio_source audiounit\n"
      "audio_player audiounit\n";
  result = conf_configure_buf(config, sizeof(config) - 1);
  if (!result) result = baresip_init(conf_config());
  if (!result) result = ua_init("OmniDesk", false, false, true);
  if (!result) result = module_load(NULL, "audiounit");
  if (!result) result = module_load(NULL, "g711");
  // SDES-SRTP media crypto. The module is self-contained (libre crypto);
  // without it an SDP offer with RTP/SAVP cannot produce audio.
  if (!result) result = module_load(NULL, "srtp");
  if (!result) [self configureTlsTrust];
  if (!result) result = uag_event_register(omni_ua_event, (__bridge void *)self);
  if (result) {
    os_log_error(OmniDeskBaresipLog(), "Baresip engine initialization failed: %d", result);
    if (error) *error = [self error:@"Unable to initialize the iOS SIP media engine." code:result];
    return NO;
  }
  pthread_t thread;
  if (pthread_create(&thread, NULL, omni_baresip_loop, NULL) != 0) {
    os_log_error(OmniDeskBaresipLog(), "Unable to start the Baresip event loop");
    if (error) *error = [self error:@"Unable to start the iOS SIP media loop." code:-1];
    return NO;
  }
  pthread_detach(thread);
  _started = YES;
  os_log_info(OmniDeskBaresipLog(), "Baresip media engine initialized");
  return YES;
}

- (void)configureTlsTrust {
  // Flutter declares assets/certs/ in pubspec.yaml, so the PEM ships inside
  // App.framework/flutter_assets. Resolved at runtime: no Xcode project edit.
  NSString *frameworks = [NSBundle.mainBundle.privateFrameworksPath
      stringByAppendingPathComponent:@"App.framework"];
  NSString *caPath = [[NSBundle bundleWithPath:frameworks]
      pathForResource:@"ca_bundle" ofType:@"pem" inDirectory:@"flutter_assets/assets/certs"];
  if (!caPath) {
    os_log_error(OmniDeskBaresipLog(), "TLS CA bundle missing from flutter_assets; SIP/TLS verification will fail");
    return;
  }
  strlcpy(conf_config()->sip.cafile, caPath.UTF8String, sizeof(conf_config()->sip.cafile));
  os_log_info(OmniDeskBaresipLog(), "TLS CA bundle configured");
}

- (NSString *)ensureRegisteredWithUri:(NSString *)uri username:(NSString *)username
                         authUsername:(NSString *)authUsername password:(NSString *)password
                            registrar:(NSString *)registrar domain:(NSString *)domain
                                proxy:(NSString *)proxy transport:(NSString *)transport
                                 port:(NSInteger)port incomingCallId:(NSString *)incomingCallId
                                  error:(NSError **)error {
  (void)username; (void)registrar; (void)domain; (void)port;
  NSString *accountUri = [self sipUri:uri transport:transport];
  NSString *outboundProxy = [self sipUri:proxy transport:transport];
  os_log_info(OmniDeskBaresipLog(), "Registering SIP account uri=%{public}s proxy=%{public}s transport=%{public}s port=%ld",
              accountUri.UTF8String, outboundProxy.UTF8String, transport.UTF8String, (long)port);
  __block NSString *session = nil;
  dispatch_sync(_queue, ^{
    if (![self startEngine:error]) {
      os_log_error(OmniDeskBaresipLog(), "Registration aborted during engine initialization");
      return;
    }
    if (!_ua) {
      int result = ua_alloc(&_ua, accountUri.UTF8String);
      if (result) {
        os_log_error(OmniDeskBaresipLog(), "ua_alloc failed: %d", result);
        if (error) *error = [self error:@"Unable to create the SIP account." code:result];
        return;
      }
      os_log_info(OmniDeskBaresipLog(), "SIP account created");
    }
    struct account *account = ua_account(_ua);
    // Establish correlation before ua_register: a synchronous transport
    // failure can emit UA_EVENT_REGISTER_FAIL from inside ua_register.
    _mediaSessionId = [NSString stringWithFormat:@"media-%@", NSUUID.UUID.UUIDString];
    _callId = [incomingCallId copy];
    _callSid = nil;
    int result = account_set_auth_user(account, authUsername.UTF8String);
    if (!result) result = account_set_auth_pass(account, password.UTF8String);
    if (!result) result = account_set_outbound(account, outboundProxy.UTF8String, 0);
    if (!result) result = account_set_regint(account, 300);
    if (!result) result = ua_register(_ua);
    if (result) {
      os_log_error(OmniDeskBaresipLog(), "SIP registration request failed: %d", result);
      if (error) *error = [self error:@"Unable to start SIP registration." code:result];
      return;
    }
    os_log_info(OmniDeskBaresipLog(), "SIP registration request accepted; awaiting registrar event");
    session = _mediaSessionId;
  });
  return session;
}

- (NSString *)startOutgoingWithCallSid:(NSString *)callSid targetSipUri:(NSString *)targetSipUri error:(NSError **)error {
  os_log_info(OmniDeskBaresipLog(), "Starting outbound SIP call sid=%{public}s target=%{public}s",
              callSid.UTF8String, targetSipUri.UTF8String);
  __block NSString *session = nil;
  dispatch_sync(_queue, ^{
    if (!_ua) {
      os_log_error(OmniDeskBaresipLog(), "Outbound call rejected: SIP account is not initialized");
      if (error) *error = [self error:@"SIP registration is not ready." code:-1];
      return;
    }
    int result = ua_connect(_ua, &_call, NULL, targetSipUri.UTF8String, VIDMODE_OFF);
    if (result) {
      os_log_error(OmniDeskBaresipLog(), "ua_connect failed: %d", result);
      if (error) *error = [self error:@"Unable to start the SIP call." code:result];
      return;
    }
    os_log_info(OmniDeskBaresipLog(), "Outbound SIP INVITE submitted");
    _callSid = [callSid copy];
    _callId = nil;
    if (!_mediaSessionId) _mediaSessionId = [NSString stringWithFormat:@"media-%@", NSUUID.UUID.UUIDString];
    session = _mediaSessionId;
  });
  return session;
}

- (BOOL)endMedia:(NSString *)mediaSessionId error:(NSError **)error {
  __block BOOL ok = YES;
  dispatch_sync(_queue, ^{
    if (_mediaSessionId && ![_mediaSessionId isEqualToString:mediaSessionId]) return;
    if (_ua && _call) ua_hangup(_ua, _call, 0, "agent_hangup");
    _call = NULL;
  });
  return ok;
}

- (BOOL)setMuted:(BOOL)enabled error:(NSError **)error {
  dispatch_sync(_queue, ^{ if (_call) audio_mute(call_audio(_call), enabled); });
  return YES;
}

- (BOOL)setHeld:(BOOL)enabled error:(NSError **)error {
  __block int result = 0;
  dispatch_sync(_queue, ^{ if (_call) result = call_hold(_call, enabled); });
  if (result && error) *error = [self error:@"Unable to change call hold state." code:result];
  return result == 0;
}

- (BOOL)sendDtmf:(NSString *)digit error:(NSError **)error {
  if (digit.length == 0) return NO;
  __block int result = 0;
  dispatch_sync(_queue, ^{ if (_call) result = call_send_digit(_call, [digit characterAtIndex:0]); });
  if (result && error) *error = [self error:@"Unable to send DTMF digit." code:result];
  return result == 0;
}

- (void)handleEvent:(enum ua_event)event
               call:(struct call *)call
             reason:(NSString *)reason {
  if (call) _call = call;
  NSString *type = nil;
  switch (event) {
    case UA_EVENT_REGISTER_OK: type = @"registered"; break;
    case UA_EVENT_REGISTER_FAIL: type = @"failed"; break;
    case UA_EVENT_CALL_RINGING: type = @"ringing"; break;
    case UA_EVENT_CALL_ESTABLISHED: type = @"connected"; break;
    case UA_EVENT_CALL_HOLD: type = @"held"; break;
    case UA_EVENT_CALL_RESUME: type = @"connected"; break;
    case UA_EVENT_CALL_CLOSED: type = @"disconnected"; _call = NULL; break;
    default: return;
  }
  os_log_info(OmniDeskBaresipLog(), "Baresip event %{public}s reason=%{public}s",
              type.UTF8String, (reason ?: @"none").UTF8String);
  OmniDeskBaresipEventHandler handler = self.handler;
  if (!handler) return;
  dispatch_async(dispatch_get_main_queue(), ^{ handler(type, reason); });
}

@end
