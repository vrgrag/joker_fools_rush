import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';

import '../env/beacon_seeds.dart';
import '../env/identity.dart';
import '../net/agent_client.dart';

/// AppsFlyer wrapper.
///
/// Differences from AdventureRoad's AppsFlyerService:
///   - Uses three named futures instead of Completers with imperative logic.
///   - GCD retry pushes _through_ the AgentClient so the UA is consistent.
///   - Attribution merging is done _once_ inside [assembleBody] so we don't
///     keep three parallel mutable maps.
class AttributionHub {
  AttributionHub();

  AppsflyerSdk? _driver;
  bool _booted = false;

  final Completer<Map<String, dynamic>> _attributionArrived =
      Completer<Map<String, dynamic>>();
  final Completer<Map<String, dynamic>> _deepLinkArrived =
      Completer<Map<String, dynamic>>();
  final Completer<Map<String, dynamic>> _appOpenArrived =
      Completer<Map<String, dynamic>>();

  Map<String, dynamic> _attribution = const <String, dynamic>{};
  Map<String, dynamic> _deepLink = const <String, dynamic>{};
  Map<String, dynamic> _appOpen = const <String, dynamic>{};

  Future<void> boot() async {
    if (_booted) return;
    _booted = true;

    final String devKey = Identity.analyticsKey;
    if (devKey.isEmpty) {
      // No key configured yet — mark all futures as complete so the flow
      // doesn't stall the entire startup.
      _completeSafe(_attributionArrived, <String, dynamic>{});
      _completeSafe(_deepLinkArrived, <String, dynamic>{});
      _completeSafe(_appOpenArrived, <String, dynamic>{});
      return;
    }

    try {
      final AppsFlyerOptions options = AppsFlyerOptions(
        afDevKey: devKey,
        appId: Identity.analyticsAppId,
        showDebug: kDebugMode,
        timeToWaitForATTUserAuthorization: 10,
      );

      _driver = AppsflyerSdk(options);

      _driver!.onInstallConversionData((dynamic data) async {
        final Map<String, dynamic> payload = _extractPayload(data);
        if (payload['af_status'] == 'Organic') {
          await Future<void>.delayed(
              Duration(seconds: Identity.gcdRetrySeconds));
          final Map<String, dynamic>? refreshed = await _refreshFromGcd();
          _attribution = refreshed ?? payload;
        } else {
          _attribution = payload;
        }
        _completeSafe(_attributionArrived, _attribution);
      });

      _driver!.onAppOpenAttribution((dynamic data) {
        _appOpen = _extractPayload(data);
        _completeSafe(_appOpenArrived, _appOpen);
      });

      _driver!.onDeepLinking((DeepLinkResult r) {
        final dynamic click = r.deepLink?.clickEvent;
        if (click is Map) {
          _deepLink = Map<String, dynamic>.from(click);
        }
        _completeSafe(_deepLinkArrived, _deepLink);
      });

      await _driver!.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );
    } catch (_) {
      _completeSafe(_attributionArrived, <String, dynamic>{});
      _completeSafe(_deepLinkArrived, <String, dynamic>{});
      _completeSafe(_appOpenArrived, <String, dynamic>{});
    }
  }

  Future<Map<String, dynamic>> waitAttribution({
    Duration limit = const Duration(seconds: 30),
  }) {
    return _attributionArrived.future
        .timeout(limit, onTimeout: () => <String, dynamic>{});
  }

  Future<Map<String, dynamic>> waitDeepLink({
    Duration limit = const Duration(seconds: 5),
  }) {
    return _deepLinkArrived.future
        .timeout(limit, onTimeout: () => <String, dynamic>{});
  }

  Future<String?> analyticsUid() async {
    if (_driver == null) return null;
    try {
      return await _driver!.getAppsFlyerUID();
    } catch (_) {
      return null;
    }
  }

  /// Assembles the POST body for the portal endpoint.
  /// Order: attribution → deep link (putIfAbsent) → app-open (putIfAbsent)
  /// → device fields (always overwrite).
  Future<Map<String, dynamic>> assembleBody({
    required String locale,
    String? pushToken,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{};
    body.addAll(_attribution);
    _deepLink.forEach((String k, dynamic v) => body.putIfAbsent(k, () => v));
    _appOpen.forEach((String k, dynamic v) => body.putIfAbsent(k, () => v));

    body['af_id'] = (await analyticsUid()) ?? '';
    body['bundle_id'] = Identity.bundleId;
    body['os'] = Platform.isAndroid ? 'Android' : 'iOS';
    body['store_id'] = Identity.storeId;
    body['locale'] = locale;
    if (pushToken != null && pushToken.isNotEmpty) {
      body['push_token'] = pushToken;
    }
    if (Identity.messagingProject.isNotEmpty) {
      body['firebase_project_id'] = Identity.messagingProject;
    }

    if (kDebugMode) {
      debugPrint('[AttributionHub] body=${jsonEncode(body)}');
    }
    return body;
  }

  // ------------------------------------------------------------------
  //  internal helpers
  // ------------------------------------------------------------------

  static Map<String, dynamic> _extractPayload(dynamic data) {
    if (data is Map) {
      final dynamic inner = data['payload'];
      if (inner is Map) return Map<String, dynamic>.from(inner);
      return Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{};
  }

  static void _completeSafe<T>(Completer<T> c, T value) {
    if (!c.isCompleted) c.complete(value);
  }

  Future<Map<String, dynamic>?> _refreshFromGcd() async {
    final String uid = await analyticsUid() ?? '';
    if (uid.isEmpty) return null;
    final String appId =
        Platform.isIOS ? Identity.analyticsAppId : Identity.bundleId;
    final String endpoint = composeGcdEndpoint(appId, uid);
    if (endpoint.isEmpty) return null;
    try {
      final response = await agentClient.get(
        Uri.parse(endpoint),
        headers: <String, String>{
          'authorization': 'Bearer ${Identity.analyticsKey}',
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }
}
