#include <jni.h>
#include <android/log.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#include <re.h>
#include <baresip.h>

/* Exactly one foreground agent media session is permitted by the UI and by
 * CallKit/Telecom. All state is confined to this native process and released
 * on terminal events; no SIP credential is written to disk or log output. */
static JavaVM *g_vm;
static jclass g_bridge_class;
static jmethodID g_emit;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static struct ua *g_ua;
static struct call *g_call;
static bool g_engine_started;
static char g_media_session[80];
static char g_call_id[128];
static char g_call_sid[128];
/* Bundled root-CA path staged by Kotlin (res/raw -> filesDir). Android ships
 * no OpenSSL default verify location, so SIP/TLS needs this explicitly. */
static char g_cafile[512];

#define LOG_TAG "OmniDeskBaresip"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static void emit_event(const char *type, const char *reason) {
  LOGI("native event=%s%s%s", type ? type : "unknown",
       reason ? " reason=" : "", reason ? reason : "");
  if (!g_vm || !g_bridge_class || !g_emit) return;
  JNIEnv *env = NULL;
  bool detach = false;
  if ((*g_vm)->GetEnv(g_vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) {
    if ((*g_vm)->AttachCurrentThread(g_vm, &env, NULL) != JNI_OK) return;
    detach = true;
  }
  jstring jtype = (*env)->NewStringUTF(env, type);
  jstring jcall_id = g_call_id[0] ? (*env)->NewStringUTF(env, g_call_id) : NULL;
  jstring jcall_sid = g_call_sid[0] ? (*env)->NewStringUTF(env, g_call_sid) : NULL;
  jstring jsession = g_media_session[0] ? (*env)->NewStringUTF(env, g_media_session) : NULL;
  jstring jreason = reason ? (*env)->NewStringUTF(env, reason) : NULL;
  (*env)->CallStaticVoidMethod(env, g_bridge_class, g_emit, jtype, jcall_id, jcall_sid, jsession, jreason);
  if (jtype) (*env)->DeleteLocalRef(env, jtype);
  if (jcall_id) (*env)->DeleteLocalRef(env, jcall_id);
  if (jcall_sid) (*env)->DeleteLocalRef(env, jcall_sid);
  if (jsession) (*env)->DeleteLocalRef(env, jsession);
  if (jreason) (*env)->DeleteLocalRef(env, jreason);
  if (detach) (*g_vm)->DetachCurrentThread(g_vm);
}

static void ua_event_handler(struct ua *ua, enum ua_event event,
                             struct call *call, const char *prm, void *arg) {
  (void)ua; (void)arg;
  if (call) g_call = call;
  switch (event) {
    case UA_EVENT_REGISTER_OK: emit_event("registered", NULL); break;
    case UA_EVENT_REGISTER_FAIL: emit_event("failed", "SIP registration failed."); break;
    case UA_EVENT_CALL_RINGING: emit_event("ringing", NULL); break;
    case UA_EVENT_CALL_ESTABLISHED: emit_event("connected", NULL); break;
    case UA_EVENT_CALL_HOLD: emit_event("held", NULL); break;
    case UA_EVENT_CALL_RESUME: emit_event("connected", NULL); break;
    case UA_EVENT_CALL_CLOSED:
      emit_event("disconnected", NULL);
      g_call = NULL;
      break;
    case UA_EVENT_AUDIO_ERROR: emit_event("failed", "Native audio failed."); break;
    default: break;
  }
}

static void *baresip_loop(void *unused) {
  (void)unused;
  re_main(NULL);
  return NULL;
}

static int ensure_engine(void) {
  if (g_engine_started) return 0;
  LOGI("initializing Baresip engine");
  static const uint8_t config[] =
      "sip_listen 0.0.0.0:0\n"
      "audio_source opensles\n"
      "audio_player opensles\n";
  int err = libre_init();
  if (err) { LOGE("libre initialization failed code=%d", err); return err; }
  err = conf_configure_buf(config, sizeof(config) - 1);
  if (err) { LOGE("Baresip configuration failed code=%d", err); return err; }
  if (g_cafile[0]) {
    strncpy(conf_config()->sip.cafile, g_cafile,
            sizeof(conf_config()->sip.cafile) - 1);
    LOGI("TLS CA bundle configured");
  }
  else {
    LOGW("TLS CA bundle not staged; SIP/TLS verification will fail");
  }
  err = baresip_init(conf_config());
  if (err) { LOGE("Baresip initialization failed code=%d", err); return err; }
  err = ua_init("OmniDesk", false, false, true);
  if (err) { LOGE("user-agent initialization failed code=%d", err); return err; }
  err = module_load(NULL, "opensles");
  if (err) { LOGE("audio module initialization failed code=%d", err); return err; }
  err = module_load(NULL, "g711");
  if (err) { LOGE("codec module initialization failed code=%d", err); return err; }
  /* SDES-SRTP media crypto (self-contained, libre crypto). Without it an SDP
     offer with RTP/SAVP cannot produce audio. */
  err = module_load(NULL, "srtp");
  if (err) { LOGE("srtp module initialization failed code=%d", err); return err; }
  err = uag_event_register(ua_event_handler, NULL);
  if (err) { LOGE("Baresip event registration failed code=%d", err); return err; }
  pthread_t thread;
  if (pthread_create(&thread, NULL, baresip_loop, NULL) != 0) {
    LOGE("Baresip event loop could not start");
    return -1;
  }
  pthread_detach(thread);
  g_engine_started = true;
  LOGI("Baresip engine initialized");
  return 0;
}

static jstring native_error(JNIEnv *env, const char *message) {
  jclass exception = (*env)->FindClass(env, "java/lang/IllegalStateException");
  (*env)->ThrowNew(env, exception, message);
  return NULL;
}

JNIEXPORT jstring JNICALL
Java_com_bigbrainzsolutions_omnidesk_NativeBaresip_nativeEnsureRegistered(
    JNIEnv *env, jobject thiz, jstring uri, jstring username, jstring auth_username,
    jstring password, jstring registrar, jstring domain, jstring proxy,
    jstring transport, jint port, jstring incoming_call_id) {
  (void)username; (void)registrar; (void)domain; (void)transport; (void)port;
  const char *aor = (*env)->GetStringUTFChars(env, uri, NULL);
  const char *auth_user = (*env)->GetStringUTFChars(env, auth_username, NULL);
  const char *auth_pass = (*env)->GetStringUTFChars(env, password, NULL);
  const char *outbound = (*env)->GetStringUTFChars(env, proxy, NULL);
  const char *call_id = incoming_call_id ? (*env)->GetStringUTFChars(env, incoming_call_id, NULL) : NULL;
  LOGI("SIP registration requested (incoming=%s)", call_id ? "true" : "false");
  pthread_mutex_lock(&g_lock);
  int err = ensure_engine();
  if (!err && !g_ua) err = ua_alloc(&g_ua, aor);
  if (!err) {
    struct account *account = ua_account(g_ua);
    err = account_set_auth_user(account, auth_user);
    if (!err) err = account_set_auth_pass(account, auth_pass);
    if (!err) err = account_set_outbound(account, outbound, 0);
    if (!err) err = account_set_regint(account, 300);
    if (!err) err = ua_register(g_ua);
  }
  snprintf(g_media_session, sizeof(g_media_session), "media-%ld", (long)time(NULL));
  snprintf(g_call_id, sizeof(g_call_id), "%s", call_id ? call_id : "");
  g_call_sid[0] = '\0';
  pthread_mutex_unlock(&g_lock);
  (*env)->ReleaseStringUTFChars(env, uri, aor);
  (*env)->ReleaseStringUTFChars(env, auth_username, auth_user);
  (*env)->ReleaseStringUTFChars(env, password, auth_pass);
  (*env)->ReleaseStringUTFChars(env, proxy, outbound);
  if (incoming_call_id) (*env)->ReleaseStringUTFChars(env, incoming_call_id, call_id);
  if (err) {
    LOGE("SIP registration could not be started code=%d", err);
    return native_error(env, "Unable to start SIP registration.");
  }
  LOGI("SIP registration request accepted; waiting for registrar result");
  return (*env)->NewStringUTF(env, g_media_session);
}

JNIEXPORT jstring JNICALL
Java_com_bigbrainzsolutions_omnidesk_NativeBaresip_nativeStartOutgoing(
    JNIEnv *env, jobject thiz, jstring call_sid, jstring target_sip_uri) {
  const char *sid = (*env)->GetStringUTFChars(env, call_sid, NULL);
  const char *target = (*env)->GetStringUTFChars(env, target_sip_uri, NULL);
  LOGI("outgoing SIP media requested");
  pthread_mutex_lock(&g_lock);
  int err = g_ua ? ua_connect(g_ua, &g_call, NULL, target, VIDMODE_OFF) : -1;
  snprintf(g_call_sid, sizeof(g_call_sid), "%s", sid);
  g_call_id[0] = '\0';
  pthread_mutex_unlock(&g_lock);
  (*env)->ReleaseStringUTFChars(env, call_sid, sid);
  (*env)->ReleaseStringUTFChars(env, target_sip_uri, target);
  if (err) {
    LOGE("outgoing SIP media could not be started code=%d", err);
    return native_error(env, "Unable to start SIP call.");
  }
  LOGI("outgoing SIP media request accepted; waiting for call state");
  return (*env)->NewStringUTF(env, g_media_session);
}

JNIEXPORT void JNICALL Java_com_bigbrainzsolutions_omnidesk_NativeBaresip_nativeEnd(
    JNIEnv *env, jobject thiz, jstring media_session_id) {
  (void)env; (void)thiz; (void)media_session_id;
  pthread_mutex_lock(&g_lock);
  if (g_ua) ua_hangup(g_ua, g_call, 0, "agent_hangup");
  pthread_mutex_unlock(&g_lock);
}

JNIEXPORT void JNICALL Java_com_bigbrainzsolutions_omnidesk_NativeBaresip_nativeSetMuted(
    JNIEnv *env, jobject thiz, jboolean enabled) {
  (void)env; (void)thiz;
  pthread_mutex_lock(&g_lock);
  if (g_call) audio_mute(call_audio(g_call), enabled == JNI_TRUE);
  pthread_mutex_unlock(&g_lock);
}

JNIEXPORT void JNICALL Java_com_bigbrainzsolutions_omnidesk_NativeBaresip_nativeSetHeld(
    JNIEnv *env, jobject thiz, jboolean enabled) {
  (void)env; (void)thiz;
  pthread_mutex_lock(&g_lock);
  if (g_call) call_hold(g_call, enabled == JNI_TRUE);
  pthread_mutex_unlock(&g_lock);
}

JNIEXPORT void JNICALL Java_com_bigbrainzsolutions_omnidesk_NativeBaresip_nativeSendDtmf(
    JNIEnv *env, jobject thiz, jchar digit) {
  (void)env; (void)thiz;
  pthread_mutex_lock(&g_lock);
  if (g_call) call_send_digit(g_call, (char)digit);
  pthread_mutex_unlock(&g_lock);
}

JNIEXPORT void JNICALL Java_com_bigbrainzsolutions_omnidesk_NativeBaresip_nativeSetCaFile(
    JNIEnv *env, jobject thiz, jstring ca_path) {
  (void)thiz;
  if (!ca_path) return;
  const char *path = (*env)->GetStringUTFChars(env, ca_path, NULL);
  if (path) {
    strncpy(g_cafile, path, sizeof(g_cafile) - 1);
    g_cafile[sizeof(g_cafile) - 1] = '\0';
    LOGI("TLS CA bundle staged");
  }
  (*env)->ReleaseStringUTFChars(env, ca_path, path);
}

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {
  (void)reserved;
  g_vm = vm;
  JNIEnv *env = NULL;
  if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) return JNI_ERR;
  jclass local = (*env)->FindClass(env, "com/bigbrainzsolutions/omnidesk/NativeBaresip");
  if (!local) return JNI_ERR;
  g_bridge_class = (*env)->NewGlobalRef(env, local);
  g_emit = (*env)->GetStaticMethodID(env, g_bridge_class, "emit", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V");
  return g_emit ? JNI_VERSION_1_6 : JNI_ERR;
}
