import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Runtime configuration for the WebSocket layer.
///
/// Sourced from `.env` so dev / staging / production can point at different
/// Reverb hosts without code changes. All values have safe defaults and the
/// whole realtime layer can be disabled via `REALTIME_ENABLED=false`.
class RealtimeConfig {
  const RealtimeConfig({
    required this.enabled,
    required this.appKey,
    required this.cluster,
    required this.host,
    required this.wsPort,
    required this.wssPort,
    required this.useTls,
    required this.httpAuthEndpoint,
  });

  final bool enabled;
  final String appKey;
  final String cluster;
  final String host;
  final int wsPort;
  final int wssPort;
  final bool useTls;
  final String? httpAuthEndpoint;

  static RealtimeConfig fromEnv([Map<String, String>? override]) {
    final env = override ?? dotenv.env;
    String read(String key, String fallback) {
      final value = env[key];
      if (value == null || value.trim().isEmpty) return fallback;
      return value.trim();
    }

    int readPort(String key, int fallback) {
      final port = int.tryParse(read(key, '$fallback'));
      // A URI with port 0 is syntactically valid but never a usable remote
      // WebSocket endpoint. Treat malformed/out-of-range environment values
      // as absent so production defaults (80/443) still apply.
      return port != null && port > 0 && port <= 65535 ? port : fallback;
    }

    bool readBool(String key, bool fallback) {
      final raw = read(key, fallback ? 'true' : 'false').toLowerCase();
      if (raw == 'true' || raw == '1' || raw == 'yes') return true;
      if (raw == 'false' || raw == '0' || raw == 'no') return false;
      return fallback;
    }

    // Derive a sensible default host from API_BASE_URL when REVERB_HOST is
    // not set (e.g. ngrok / production domains).
    String defaultHost = '127.0.0.1';
    final apiBase = read('API_BASE_URL', '');
    final apiUri = Uri.tryParse(apiBase);
    if (apiUri != null && apiUri.host.isNotEmpty) {
      defaultHost = apiUri.host;
    }

    final useTlsDefault = apiUri?.scheme == 'https';
    final useTls = readBool('REVERB_USE_TLS', useTlsDefault);

    // Port defaults: local Reverb listens on 8086, but a remote host
    // (ngrok / production proxy) almost never exposes 8086 — default to the
    // scheme ports unless explicitly overridden. This is what broke the
    // ngrok session: wss://<ngrok-host>:8086/... is unreachable, while
    // wss://<ngrok-host>/app/<key> (443) routes through the tunnel.
    bool has(String key) =>
        env.containsKey(key) && (env[key] ?? '').trim().isNotEmpty;
    final host = read('REVERB_HOST', defaultHost);
    final hostIsLoopback =
        host == '127.0.0.1' || host == 'localhost' || host == '10.0.2.2';

    return RealtimeConfig(
      enabled: readBool('REALTIME_ENABLED', true),
      appKey: read('REVERB_APP_KEY', 'bigbrainz_widget_key'),
      cluster: read('REVERB_CLUSTER', 'mt1'),
      host: host,
      wsPort: has('REVERB_WS_PORT')
          ? readPort('REVERB_WS_PORT', hostIsLoopback ? 8086 : 80)
          : (hostIsLoopback ? 8086 : 80),
      wssPort: has('REVERB_WSS_PORT')
          ? readPort('REVERB_WSS_PORT', hostIsLoopback ? 8086 : 443)
          : (hostIsLoopback ? 8086 : 443),
      useTls: useTls,
      httpAuthEndpoint: (() {
        final v = read('REVERB_AUTH_ENDPOINT', '');
        return v.isEmpty ? null : v;
      })(),
    );
  }

  bool get isLoopback =>
      host == '127.0.0.1' || host == 'localhost' || host == '10.0.2.2';
}
