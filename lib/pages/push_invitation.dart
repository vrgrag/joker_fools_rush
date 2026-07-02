import 'package:flutter/material.dart';

import '../env/identity.dart';
import '../gate/alert_courier.dart';
import '../net/net_sensor.dart';
import '../vault/local_vault.dart';
import 'portal_view.dart' deferred as web;

/// Notification permission invitation.
/// - Uses two orientation-aware backgrounds (notification_vertical /
///   notification_horizontal) as the whole visual layer.
/// - "Accept" pulses; "Skip" is a plain subdued text button.
/// - On denial (system dialog says No), stores the "OS blocked" flag so
///   the screen isn't re-offered — Android 13+ won't show the dialog again.
class PushInvitationPage extends StatefulWidget {
  const PushInvitationPage({
    super.key,
    required this.courier,
    required this.sensor,
    required this.targetUrl,
  });

  final AlertCourier courier;
  final NetSensor sensor;
  final String targetUrl;

  @override
  State<PushInvitationPage> createState() => _PushInvitationPageState();
}

class _PushInvitationPageState extends State<PushInvitationPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.courier.askPermission();
    if (!mounted) return;
    // Whatever the outcome — proceed to the WebPortal. If not granted,
    // schedule the next prompt window.
    if (!LocalVault.instance.notifGranted()) {
      final int ts = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
          Identity.notificationDeferSeconds;
      await LocalVault.instance.writeSkipUntil(ts);
    }
    await _openPortal();
  }

  Future<void> _skip() async {
    if (_busy) return;
    setState(() => _busy = true);
    final int ts = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
        Identity.notificationDeferSeconds;
    await LocalVault.instance.writeSkipUntil(ts);
    if (!mounted) return;
    await _openPortal();
  }

  Future<void> _openPortal() async {
    await web.loadLibrary();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => web.WebPortal(
          targetUrl: widget.targetUrl,
          sensor: widget.sensor,
          courier: widget.courier,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final bool landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final String bg = landscape
        ? 'assets/notification_horizontal.webp'
        : 'assets/notification_vertical.webp';

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.asset(bg, fit: BoxFit.cover),
            if (!landscape)
              Positioned(
                left: size.width * 0.09,
                right: size.width * 0.09,
                bottom: size.height * 0.08,
                child: _actionColumn(),
              )
            else
              Positioned(
                left: 0,
                right: 0,
                bottom: size.height * 0.03,
                child: Center(
                  child: SizedBox(
                    width: size.width * 0.28,
                    child: _actionColumn(compact: true),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _actionColumn({bool compact = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _AcceptDiamond(
          onTap: _accept,
          pulse: _pulse,
          compact: compact,
        ),
        SizedBox(height: compact ? 6 : 14),
        _SkipLink(onTap: _skip, compact: compact),
      ],
    );
  }
}

class _AcceptDiamond extends StatefulWidget {
  const _AcceptDiamond({
    required this.onTap,
    required this.pulse,
    required this.compact,
  });
  final VoidCallback onTap;
  final AnimationController pulse;
  final bool compact;

  @override
  State<_AcceptDiamond> createState() => _AcceptDiamondState();
}

class _AcceptDiamondState extends State<_AcceptDiamond> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.pulse,
      builder: (BuildContext _, Widget? child) {
        final double glow = 0.4 + widget.pulse.value * 0.5;
        return GestureDetector(
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) {
            setState(() => _down = false);
            widget.onTap();
          },
          child: AnimatedScale(
            scale: _down ? 0.95 : 1.0,
            duration: const Duration(milliseconds: 90),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                  vertical: widget.compact ? 7 : 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _down
                      ? const <Color>[Color(0xFF5B21B6), Color(0xFF2A0E5B)]
                      : const <Color>[Color(0xFF9F7AEA), Color(0xFF4C1D95)],
                ),
                borderRadius:
                    const BorderRadius.all(Radius.elliptical(28, 22)),
                border: Border.all(
                    color: const Color(0xFFFFC107), width: 2.4),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFFFFC107).withValues(alpha: glow),
                    blurRadius: 22 + glow * 8,
                    spreadRadius: glow * 2,
                  ),
                  const BoxShadow(
                    color: Colors.black45,
                    offset: Offset(0, 4),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  'Accept',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: widget.compact ? 13 : 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: widget.compact ? 1.6 : 2.4,
                    shadows: const <Shadow>[
                      Shadow(color: Colors.black, blurRadius: 6),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SkipLink extends StatefulWidget {
  const _SkipLink({required this.onTap, required this.compact});
  final VoidCallback onTap;
  final bool compact;

  @override
  State<_SkipLink> createState() => _SkipLinkState();
}

class _SkipLinkState extends State<_SkipLink> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      child: AnimatedOpacity(
        opacity: _down ? 0.5 : 0.85,
        duration: const Duration(milliseconds: 80),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: widget.compact ? 2 : 8),
          child: Center(
            child: Text(
              'Skip',
              style: TextStyle(
                color: Colors.white,
                fontSize: widget.compact ? 12 : 20,
                fontWeight: FontWeight.w700,
                letterSpacing: widget.compact ? 1.0 : 1.6,
                shadows: const <Shadow>[
                  Shadow(
                      color: Colors.black54,
                      blurRadius: 6,
                      offset: Offset(0, 2)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
