import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'board_levels.dart';
import 'board_palette.dart';
import 'board_vault.dart';

class BoardRun extends StatefulWidget {
  const BoardRun({super.key, required this.level});

  final int level;

  @override
  State<BoardRun> createState() => _BoardRunState();
}

enum _RunPhase { playing, paused, won, lost }

class _BoardRunState extends State<BoardRun>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final LevelConfig _config;

  Duration _lastTick = Duration.zero;

  // World coordinates: y grows downward, measured in screen heights (1.0 = screen height).
  // x measured in 0..1 (fraction of screen width).
  double _cameraY = 0; // top of camera in world units
  double _jokerX = 0.5; // 0..1
  double _targetJokerX = 0.5;
  final double _jokerYInWorld = 0.15; // stays fixed as camera scrolls

  int _coins = 0;
  int _hearts = 3;
  double _invulnUntil = 0; // world time (seconds) invuln until

  double _time = 0;

  _RunPhase _state = _RunPhase.playing;

  // Consumed items keyed by "row-idx:type:index-in-list"
  final Set<String> _consumed = <String>{};

  // The Joker size (in world x-units and world y-units).
  static const double _jokerWidth = 0.14;
  static const double _jokerHeight = 0.12; // in world height units

  // Platform visual thickness (world height units).
  static const double _platformThickness = 0.045;

  // Hazard height (world height units).
  static const double _hazardHeight = 0.06;

  @override
  void initState() {
    super.initState();
    _config = LevelConfig.forLevel(widget.level);
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    if (_state != _RunPhase.playing) {
      _lastTick = elapsed;
      return;
    }
    final double dt = _lastTick == Duration.zero
        ? 0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0) return;

    _time += dt;

    // Camera falls at level's fall speed.
    _cameraY += _config.fallSpeed * dt;

    // Smoothly move joker toward target.
    final double lerp = (dt * 12).clamp(0.0, 1.0);
    _jokerX = _jokerX + (_targetJokerX - _jokerX) * lerp;
    _jokerX = _jokerX.clamp(_jokerWidth / 2, 1 - _jokerWidth / 2);

    _checkCollisions();

    if (_cameraY >= _config.length) {
      _win();
    }

    if (mounted) setState(() {});
  }

  void _checkCollisions() {
    // Joker world Y position (in screens from top of level).
    final double jokerYWorld = _cameraY + _jokerYInWorld;
    final double jokerTop = jokerYWorld - _jokerHeight * 0.5;
    final double jokerBottom = jokerYWorld + _jokerHeight * 0.5;
    final double jokerLeft = _jokerX - _jokerWidth * 0.5;
    final double jokerRight = _jokerX + _jokerWidth * 0.5;

    final bool invuln = _time < _invulnUntil;

    for (int r = 0; r < _config.rows.length; r++) {
      final LevelRow row = _config.rows[r];
      // Rough vertical culling.
      if (row.y < jokerTop - 0.2) continue;
      if (row.y > jokerBottom + 0.2) continue;

      // Platform collision (rectangle around row.y with _platformThickness).
      final double pTop = row.y - _platformThickness * 0.5;
      final double pBottom = row.y + _platformThickness * 0.5;
      final bool vOverlap = jokerBottom > pTop && jokerTop < pBottom;
      if (vOverlap) {
        for (final PlatformSpec p in row.platforms) {
          final bool hOverlap = jokerRight > p.x && jokerLeft < p.right;
          if (hOverlap && !invuln) {
            _hit();
            return;
          }
        }
      }

      // Hazard collision.
      final double hTop = row.y - _hazardHeight;
      final double hBottom = row.y;
      final bool vHazard = jokerBottom > hTop && jokerTop < hBottom;
      if (vHazard) {
        for (int i = 0; i < row.hazards.length; i++) {
          final HazardSpec h = row.hazards[i];
          final String key = 'h:$r:$i';
          if (_consumed.contains(key)) continue;
          final bool hOverlap = jokerRight > h.x && jokerLeft < h.x + h.width;
          if (hOverlap && !invuln) {
            _consumed.add(key);
            _hit();
            return;
          }
        }
      }

      // Coin collection.
      final double cTop = row.y - 0.06;
      final double cBottom = row.y + 0.06;
      final bool vCoin = jokerBottom > cTop && jokerTop < cBottom;
      if (vCoin) {
        for (int i = 0; i < row.coins.length; i++) {
          final CoinSpec c = row.coins[i];
          final String key = 'c:$r:$i';
          if (_consumed.contains(key)) continue;
          final double cx = c.x;
          final double cw = 0.09;
          final bool hOverlap = jokerRight > cx - cw / 2 &&
              jokerLeft < cx + cw / 2;
          if (hOverlap) {
            _consumed.add(key);
            _coins++;
          }
        }
      }
    }
  }

  void _hit() {
    _hearts--;
    _invulnUntil = _time + 1.2;
    if (_hearts <= 0) {
      _lose();
    }
  }

  void _win() {
    if (_state != _RunPhase.playing) return;
    _state = _RunPhase.won;
    final int stars = _computeStars();
    BoardVault.instance.completeStage(widget.level, stars, _coins);
    setState(() {});
  }

  void _lose() {
    if (_state != _RunPhase.playing) return;
    _state = _RunPhase.lost;
    setState(() {});
  }

  int _computeStars() {
    // 1 star for finishing, 2 for keeping 2+ hearts, 3 for full hearts.
    if (_hearts >= 3) return 3;
    if (_hearts == 2) return 2;
    return 1;
  }

  void _restart() {
    setState(() {
      _config;
      _cameraY = 0;
      _jokerX = 0.5;
      _targetJokerX = 0.5;
      _coins = 0;
      _hearts = 3;
      _invulnUntil = 0;
      _time = 0;
      _consumed.clear();
      _state = _RunPhase.playing;
      _lastTick = Duration.zero;
    });
  }

  void _pause() {
    if (_state == _RunPhase.playing) {
      setState(() => _state = _RunPhase.paused);
    }
  }

  void _resume() {
    if (_state == _RunPhase.paused) {
      _lastTick = Duration.zero;
      setState(() => _state = _RunPhase.playing);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BoardPalette.background,
      body: LayoutBuilder(
        builder: (BuildContext ctx, BoxConstraints c) {
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // Scrolling background (tiled for endless feel).
              _buildBackground(c),
              // World content.
              _buildWorld(c),
              // Input.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (DragUpdateDetails d) {
                  final double dx = d.delta.dx / c.maxWidth;
                  _targetJokerX = (_targetJokerX + dx * 1.6).clamp(0.0, 1.0);
                },
                onTapDown: (TapDownDetails d) {
                  final double xFrac = d.localPosition.dx / c.maxWidth;
                  _targetJokerX = xFrac.clamp(0.0, 1.0);
                },
              ),
              // HUD.
              _buildHud(c),
              // Overlays.
              if (_state == _RunPhase.paused) _buildPauseOverlay(),
              if (_state == _RunPhase.won) _buildWinOverlay(),
              if (_state == _RunPhase.lost) _buildLoseOverlay(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBackground(BoxConstraints c) {
    // Repeat the background vertically and offset it by camera position.
    final double tileHeight = c.maxHeight;
    final double offset = (_cameraY * c.maxHeight) % tileHeight;
    return ClipRect(
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 0,
            right: 0,
            top: -offset,
            height: tileHeight,
            child: Image.asset('assets/playing_bg.webp', fit: BoxFit.cover),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: tileHeight - offset,
            height: tileHeight,
            child: Image.asset('assets/playing_bg.webp', fit: BoxFit.cover),
          ),
          Container(color: Colors.black.withValues(alpha: 0.35)),
        ],
      ),
    );
  }

  Widget _buildWorld(BoxConstraints c) {
    final double w = c.maxWidth;
    final double h = c.maxHeight;

    final List<Widget> items = <Widget>[];

    for (int r = 0; r < _config.rows.length; r++) {
      final LevelRow row = _config.rows[r];
      final double screenY = (row.y - _cameraY) * h;
      // Cull off-screen rows.
      if (screenY < -h * 0.3) continue;
      if (screenY > h * 1.2) continue;

      // Platforms.
      for (final PlatformSpec p in row.platforms) {
        items.add(Positioned(
          left: p.x * w,
          top: screenY - (_platformThickness * h) * 0.5,
          width: p.width * w,
          height: _platformThickness * h * 2.4,
          child: IgnorePointer(
            child: Image.asset(
              suitAsset(p.suit),
              fit: BoxFit.fill,
            ),
          ),
        ));
      }

      // Hazards.
      for (int i = 0; i < row.hazards.length; i++) {
        final HazardSpec hz = row.hazards[i];
        if (_consumed.contains('h:$r:$i')) continue;
        final String asset = hz.type == HazardType.thorns
            ? 'assets/thorns.webp'
            : 'assets/small_devil_jester.webp';
        items.add(Positioned(
          left: hz.x * w,
          top: screenY - _hazardHeight * h,
          width: hz.width * w,
          height: _hazardHeight * h * 1.4,
          child: IgnorePointer(
            child: Image.asset(asset, fit: BoxFit.contain),
          ),
        ));
      }

      // Coins.
      for (int i = 0; i < row.coins.length; i++) {
        final CoinSpec coin = row.coins[i];
        if (_consumed.contains('c:$r:$i')) continue;
        final double sz = 0.09 * w;
        items.add(Positioned(
          left: coin.x * w - sz * 0.5,
          top: screenY - sz * 0.5,
          width: sz,
          height: sz,
          child: IgnorePointer(
            child: Image.asset('assets/gold_coin.webp', fit: BoxFit.contain),
          ),
        ));
      }
    }

    // Joker.
    final double jw = _jokerWidth * w;
    final double jh = _jokerHeight * h * 1.6;
    final double jScreenY = _jokerYInWorld * h;
    final bool blink = _time < _invulnUntil && ((_time * 12).floor() % 2 == 0);
    items.add(Positioned(
      left: _jokerX * w - jw * 0.5,
      top: jScreenY - jh * 0.5,
      width: jw,
      height: jh,
      child: IgnorePointer(
        child: Opacity(
          opacity: blink ? 0.35 : 1.0,
          child: Image.asset(
            _state == _RunPhase.lost
                ? 'assets/chester_dead.webp'
                : 'assets/chester_gothik.webp',
            fit: BoxFit.contain,
          ),
        ),
      ),
    ));

    return Stack(children: items);
  }

  Widget _buildHud(BoxConstraints c) {
    final double progress = (_cameraY / _config.length).clamp(0.0, 1.0);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                _HudButton(
                  icon: Icons.pause,
                  onTap: _pause,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: BoardPalette.accent, width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: progress,
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
                  ),
                ),
                const SizedBox(width: 10),
                _StatChip(
                  icon: Icons.favorite,
                  label: '$_hearts',
                  color: BoardPalette.danger,
                ),
                const SizedBox(width: 6),
                _StatChip(
                  icon: Icons.monetization_on,
                  label: '$_coins',
                  color: BoardPalette.accent,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'LEVEL ${widget.level}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                letterSpacing: 3,
                fontWeight: FontWeight.w700,
                shadows: <Shadow>[Shadow(color: Colors.black, blurRadius: 6)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPauseOverlay() {
    return _CenterPanel(
      title: 'PAUSED',
      children: <Widget>[
        _PanelButton(label: 'RESUME', onTap: _resume),
        _PanelButton(
          label: 'RESTART',
          onTap: _restart,
        ),
        _PanelButton(
          label: 'MENU',
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildWinOverlay() {
    final int stars = _computeStars();
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Container(color: Colors.black.withValues(alpha: 0.6)),
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: BoardPalette.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: BoardPalette.accent, width: 3),
              boxShadow: <BoxShadow>[
                BoxShadow(
                    color: BoardPalette.primary.withValues(alpha: 0.6),
                    blurRadius: 20),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'LEVEL COMPLETE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: BoardPalette.accent,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List<Widget>.generate(3, (int i) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        Icons.star,
                        size: 46,
                        color: i < stars
                            ? BoardPalette.accent
                            : Colors.white24,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                Text(
                  'Coins collected: $_coins',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 16, letterSpacing: 1),
                ),
                const SizedBox(height: 20),
                _PanelButton(
                  label: 'NEXT LEVEL',
                  primary: true,
                  onTap: widget.level >= kBoardLevelCount
                      ? () => Navigator.of(context).pop()
                      : () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  BoardRun(level: widget.level + 1),
                            ),
                          );
                        },
                ),
                _PanelButton(label: 'REPLAY', onTap: _restart),
                _PanelButton(
                  label: 'MENU',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoseOverlay() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Image.asset('assets/game_over_bg.webp', fit: BoxFit.cover),
        Container(color: Colors.black.withValues(alpha: 0.5)),
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: BoardPalette.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: BoardPalette.danger, width: 3),
              boxShadow: <BoxShadow>[
                BoxShadow(
                    color: BoardPalette.danger.withValues(alpha: 0.6),
                    blurRadius: 20),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'GAME OVER',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: BoardPalette.danger,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 20),
                _PanelButton(
                  label: 'RETRY',
                  primary: true,
                  onTap: _restart,
                ),
                _PanelButton(
                  label: 'MENU',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HudButton extends StatelessWidget {
  const _HudButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: BoardPalette.accent, width: 2),
          ),
          child: Icon(icon, color: BoardPalette.accent, size: 22),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(
      {required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterPanel extends StatelessWidget {
  const _CenterPanel({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Container(color: Colors.black.withValues(alpha: 0.65)),
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: BoardPalette.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: BoardPalette.accent, width: 3),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: BoardPalette.accent,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 20),
                ...children,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton(
      {required this.label, required this.onTap, this.primary = false});
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        width: 240,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Ink(
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: primary
                      ? const <Color>[Color(0xFFB388FF), Color(0xFF6A1B9A)]
                      : const <Color>[Color(0xFF3A1B4A), Color(0xFF1A0B24)],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: BoardPalette.accent, width: 2),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: primary ? Colors.white : BoardPalette.accent,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
