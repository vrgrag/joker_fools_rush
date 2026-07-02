import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../entities/verdict_payload.dart';
import '../env/identity.dart';
import '../vault/local_vault.dart';
import 'agent_client.dart';

/// Posts the attribution+device payload to the portal endpoint and
/// returns a verdict describing whether to show the WebView shell.
///
/// Follows gray_resume_recheck.mdc — the gateway is polled on every
/// launch. A fresh URL replaces the cached one. The cached URL is
/// only used as a fallback when the network round-trip fails.
class VerdictGateway {
  VerdictGateway();

  static const Duration _kTimeout = Duration(seconds: 12);

  Future<VerdictPayload> ask(Map<String, dynamic> body) async {
    final String endpoint = Identity.portalEndpoint;
    if (endpoint.isEmpty) {
      _log('endpoint empty');
      return VerdictPayload.failure('endpoint not configured');
    }

    _log('POST $endpoint');
    try {
      final http.Response response = await agentClient
          .post(
            Uri.parse(endpoint),
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(_kTimeout);

      _log('status=${response.statusCode} body=${response.body}');

      // Some gray backends return HTTP 4xx with a valid JSON envelope
      // (e.g. { "ok": false, "message": "No data" }) when no config
      // exists for the caller. Parse any status where the body is valid
      // JSON — we only bail out on transport errors / non-JSON bodies.
      Map<String, dynamic>? raw;
      try {
        raw = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        raw = null;
      }

      if (raw == null) {
        return VerdictPayload.failure('non-json status=${response.statusCode}');
      }

      final VerdictPayload verdict = VerdictPayload.parse(raw);

      if (verdict.allowed && verdict.targetUrl != null) {
        await LocalVault.instance.pushSavedUrl(verdict.targetUrl!);
        if (verdict.expiresAt != null) {
          await LocalVault.instance.writeExpiryTs(verdict.expiresAt!);
        }
      }

      return verdict;
    } on TimeoutException {
      _log('timeout after ${_kTimeout.inSeconds}s');
      return VerdictPayload.failure('timeout');
    } catch (e) {
      _log('error: $e');
      return VerdictPayload.failure(e.toString());
    }
  }

  static void _log(String msg) {
    // ignore: avoid_print
    print('[VerdictGateway] $msg');
  }

  /// Convenience: reads the cached URL from the secure vault.
  Future<String?> cachedUrl() async {
    return LocalVault.instance.pullSavedUrl();
  }
}

