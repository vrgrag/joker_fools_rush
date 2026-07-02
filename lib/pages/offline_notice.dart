import 'package:flutter/material.dart';

/// Full-screen offline notice.
/// The visual layer is the custom `no_internet_*.webp` assets — a Retry
/// button is overlaid at a fixed bottom fraction so both orientations
/// share the same button placement rule.
class OfflineNotice extends StatefulWidget {
  const OfflineNotice({super.key, required this.onRetry});

  final void Function(BuildContext ctx) onRetry;

  @override
  State<OfflineNotice> createState() => _OfflineNoticeState();
}

class _OfflineNoticeState extends State<OfflineNotice>
    with SingleTickerProviderStateMixin {
  bool _reconnecting = false;
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    if (_reconnecting) return;
    await _press.forward();
    await _press.reverse();
    setState(() => _reconnecting = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    widget.onRetry(context);
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final bool landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final String bg = landscape
        ? 'assets/no_internet_horizontal.webp'
        : 'assets/no_internet_vertical.webp';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(bg, fit: BoxFit.cover),
          Positioned(
            left: size.width * (landscape ? 0.32 : 0.12),
            right: size.width * (landscape ? 0.32 : 0.12),
            bottom: size.height * (landscape ? 0.10 : 0.09),
            child: ScaleTransition(
              scale: Tween<double>(begin: 1.0, end: 0.94).animate(
                CurvedAnimation(parent: _press, curve: Curves.easeOut),
              ),
              child: _RetryDiamond(
                onTap: _retry,
                reconnecting: _reconnecting,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RetryDiamond extends StatelessWidget {
  const _RetryDiamond({required this.onTap, required this.reconnecting});
  final VoidCallback onTap;
  final bool reconnecting;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: reconnecting ? null : onTap,
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          gradient: reconnecting
              ? null
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Color(0xFF9F7AEA), Color(0xFF4C1D95)],
                ),
          color: reconnecting
              ? const Color(0xFF9F7AEA).withValues(alpha: 0.3)
              : null,
          borderRadius: const BorderRadius.all(Radius.elliptical(28, 22)),
          border: Border.all(color: const Color(0xFFFFC107), width: 2.4),
          boxShadow: reconnecting
              ? const <BoxShadow>[]
              : const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x99B388FF),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Colors.black38,
                    offset: Offset(0, 4),
                    blurRadius: 8,
                  ),
                ],
        ),
        child: Center(
          child: reconnecting
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFFFFC107)),
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Reconnecting...',
                      style: TextStyle(
                        color: Color(0xFFFFC107),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                )
              : const Text(
                  'Retry',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.4,
                    shadows: <Shadow>[
                      Shadow(color: Colors.black, blurRadius: 6),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
