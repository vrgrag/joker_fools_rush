import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'level_select_screen.dart';
import 'webview_screen.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset('assets/main_bg_vertical.webp', fit: BoxFit.cover),
          Container(color: Colors.black.withValues(alpha: 0.35)),
          SafeArea(
            child: Column(
              children: <Widget>[
                const Spacer(),
                _MenuButton(
                  label: 'PLAY',
                  primary: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const LevelSelectScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _MenuButton(
                  label: 'PRIVACY POLICY',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const WebViewScreen(
                        title: 'Privacy Policy',
                        url: 'https://foolsrussh.com/privacy-policy.html',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _MenuButton(
                  label: 'SUPPORT',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const WebViewScreen(
                        title: 'Support',
                        url: 'https://foolsrussh.com/support.html',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            height: primary ? 76 : 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: primary
                    ? const <Color>[Color(0xFFB388FF), Color(0xFF6A1B9A)]
                    : const <Color>[Color(0xFF3A1B4A), Color(0xFF1A0B24)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.accent, width: 2),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.5),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: primary ? Colors.white : AppTheme.accent,
                  fontSize: primary ? 28 : 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  shadows: const <Shadow>[
                    Shadow(color: Colors.black, blurRadius: 6),
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
