# Java-WebSocket/Pusher uses slf4j-api as an optional logging facade. The
# matching no-op binding is packaged explicitly in app/build.gradle.kts.

# libjingle_peerconnection_so.so resolves Java classes and methods by their
# original JNI names. R8 cannot see those native references. In particular,
# JNI_OnLoad calls org.jni_zero.JniZero.init() before PeerConnectionFactory
# can initialize; removing that class aborts the process in release builds.
# Keep the WebRTC API and the generated JNI bootstrap entry point. The SDK's
# JniZero.setJniClassLoader references an optional, unbundled JniZeroJni class;
# retaining every org.jni_zero method would make R8 fail on that unused API.
-keep class org.webrtc.** { *; }
-keep class org.jni_zero.JniZero {
    private static java.lang.Object[] init();
}
