import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/progress_service.dart';
import '../theme/app_theme.dart';
import 'menu_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _totalDuration = Duration(milliseconds: 3200);

  late final AnimationController _progressController;
  Timer? _dotsTimer;
  int _dots = 0;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    // Allow both orientations on the loading screen only.
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _progressController = AnimationController(
      vsync: this,
      duration: _totalDuration,
    );

    _dotsTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      setState(() => _dots = (_dots + 1) % 4);
    });

    _startPreload();
  }

  Future<void> _startPreload() async {
    // Hard safety cap – no matter what, we navigate after this.
    Timer(const Duration(seconds: 8), _goToMenu);

    // Fire and forget: preload assets and prefs, but never let a single
    // failure block the loading flow.
    unawaited(_safePrefs());

    // Wait one frame so precacheImage has a valid live context.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    unawaited(_safePrecacheImages());

    _progressController.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        _finishAndGo();
      }
    });
    _progressController.forward();
  }

  Future<void> _finishAndGo() async {
    if (!mounted) return;
    _progressController.value = 1.0;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _goToMenu();
  }

  Future<void> _safePrefs() async {
    try {
      await ProgressService.instance.load();
    } catch (_) {}
  }

  Future<void> _safePrecacheImages() async {
    const List<String> assets = <String>[
      'assets/main_bg_vertical.webp',
      'assets/main_bg_horizontal.webp',
      'assets/playing_bg.webp',
      'assets/game_over_bg.webp',
      'assets/chester_gothik.webp',
      'assets/chester_dead.webp',
      'assets/chester_platform.webp',
      'assets/hearts_platform.webp',
      'assets/bubna_platform.webp',
      'assets/kresti_platform.webp',
      'assets/pika_platform.webp',
      'assets/thorns.webp',
      'assets/small_devil_jester.webp',
      'assets/gold_coin.webp',
      'assets/logo.webp',
      'assets/icon.png',
    ];
    for (final String a in assets) {
      if (!mounted) return;
      try {
        await precacheImage(AssetImage(a), context);
      } catch (_) {
        // Ignore individual asset failures; loading must not hang.
      }
    }
  }

  void _goToMenu() {
    if (_navigated || !mounted) return;
    _navigated = true;
    // Lock back to portrait for the rest of the game.
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const MenuScreen()),
    );
  }

  @override
  void dispose() {
    _dotsTimer?.cancel();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: OrientationBuilder(
        builder: (BuildContext context, Orientation orientation) {
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
                    _buildProgress(context),
                    const SizedBox(height: 24),
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

  Widget _buildProgress(BuildContext context) {
    final double width = MediaQuery.of(context).size.width * 0.75;
    return AnimatedBuilder(
      animation: _progressController,
      builder: (BuildContext context, Widget? child) {
        return Container(
          width: width,
          height: 22,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.accent, width: 2),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.5),
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
                widthFactor: _progressController.value.clamp(0.0, 1.0),
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
      },
    );
  }
}
