import 'package:flutter/material.dart';

import '../game/level_data.dart';
import '../services/progress_service.dart';
import '../theme/app_theme.dart';
import 'game_screen.dart';

class LevelSelectScreen extends StatefulWidget {
  const LevelSelectScreen({super.key});

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen> {
  @override
  Widget build(BuildContext context) {
    final int unlocked = ProgressService.instance.unlockedLevels;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset('assets/main_bg_vertical.webp', fit: BoxFit.cover),
          Container(color: Colors.black.withValues(alpha: 0.55)),
          SafeArea(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: <Widget>[
                      IconButton(
                        icon: const Icon(Icons.arrow_back,
                            color: AppTheme.accent, size: 30),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Expanded(
                        child: Text(
                          'SELECT LEVEL',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.accent,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3,
                            shadows: <Shadow>[
                              Shadow(color: Colors.black, blurRadius: 8),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GridView.builder(
                      itemCount: kTotalLevels,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1,
                      ),
                      itemBuilder: (BuildContext context, int index) {
                        final int level = index + 1;
                        final bool locked = level > unlocked;
                        final int stars =
                            ProgressService.instance.starsFor(level);
                        return _LevelTile(
                          level: level,
                          locked: locked,
                          stars: stars,
                          onTap: locked
                              ? null
                              : () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          GameScreen(level: level),
                                    ),
                                  );
                                  if (mounted) setState(() {});
                                },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelTile extends StatelessWidget {
  const _LevelTile({
    required this.level,
    required this.locked,
    required this.stars,
    required this.onTap,
  });

  final int level;
  final bool locked;
  final int stars;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: locked
                  ? const <Color>[Color(0xFF2A1A34), Color(0xFF120818)]
                  : const <Color>[Color(0xFF6A1B9A), Color(0xFF2A0E3A)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: locked ? Colors.white24 : AppTheme.accent,
              width: 2,
            ),
            boxShadow: locked
                ? null
                : <BoxShadow>[
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.4),
                      blurRadius: 10,
                    ),
                  ],
          ),
          child: Stack(
            children: <Widget>[
              Center(
                child: locked
                    ? const Icon(Icons.lock, color: Colors.white54, size: 26)
                    : Text(
                        '$level',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          shadows: <Shadow>[
                            Shadow(color: Colors.black, blurRadius: 4),
                          ],
                        ),
                      ),
              ),
              if (!locked)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 6,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List<Widget>.generate(3, (int i) {
                      return Icon(
                        Icons.star,
                        size: 12,
                        color: i < stars
                            ? AppTheme.accent
                            : Colors.white24,
                      );
                    }),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
