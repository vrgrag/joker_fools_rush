import 'dart:math';

/// Total number of levels in the game.
const int kTotalLevels = 40;

enum PlatformSuit { hearts, diamonds, clubs, spades, joker }

class PlatformSpec {
  const PlatformSpec({
    required this.x,
    required this.width,
    required this.suit,
  });

  /// Left edge in 0..1 world units (of screen width).
  final double x;

  /// Width in 0..1 world units.
  final double width;

  final PlatformSuit suit;

  double get right => x + width;
}

class HazardSpec {
  const HazardSpec({required this.x, required this.width, required this.type});

  final double x;
  final double width;
  final HazardType type;
}

enum HazardType { thorns, devil }

class CoinSpec {
  const CoinSpec({required this.x});
  final double x;
}

/// A horizontal row of world content at [y] world-units from the start.
class LevelRow {
  const LevelRow({
    required this.y,
    this.platforms = const <PlatformSpec>[],
    this.hazards = const <HazardSpec>[],
    this.coins = const <CoinSpec>[],
  });

  final double y;
  final List<PlatformSpec> platforms;
  final List<HazardSpec> hazards;
  final List<CoinSpec> coins;
}

class LevelConfig {
  const LevelConfig({
    required this.number,
    required this.fallSpeed,
    required this.length,
    required this.rows,
  });

  final int number;

  /// Downward speed (world units per second, where 1 unit = 1 screen height).
  final double fallSpeed;

  /// Total length of the level in screen heights (>= 1).
  final double length;

  final List<LevelRow> rows;

  static LevelConfig forLevel(int level) {
    final int clamped = level.clamp(1, kTotalLevels);
    // Difficulty ramps up smoothly across 40 levels.
    final double t = (clamped - 1) / (kTotalLevels - 1); // 0..1

    // Fall speed grows from slow stroll to fast plunge.
    final double fallSpeed = 0.35 + 0.55 * t;

    // Level length in "screens": from ~5 screens up to ~14.
    final double length = 5 + 9 * t;

    // Row density.
    final int rowCount = (18 + 60 * t).round();

    // Row gap: how wide the safe corridor is (in screen widths).
    final double gap = 0.55 - 0.28 * t; // 0.55 -> 0.27

    // Number of hazards and enemies grows.
    final int hazardCount = (t * 12).round() + (clamped ~/ 5);
    final int devilCount = (t * 8).round();
    final int coinCount = 6 + (t * 14).round();

    final Random rng = Random(1000 + clamped * 37);

    final List<LevelRow> rows = <LevelRow>[];

    // Distribute rows evenly along the level, skipping the very top area
    // so the player can react.
    final double firstRowY = 0.9;
    final double lastRowY = length - 0.6;
    final double totalSpan = lastRowY - firstRowY;

    for (int i = 0; i < rowCount; i++) {
      final double y = firstRowY + totalSpan * (i / (rowCount - 1));

      // A safe "gap" of width [gap] is placed somewhere in [0..1].
      final double gapStart = rng.nextDouble() * (1.0 - gap);
      final double gapEnd = gapStart + gap;

      final List<PlatformSpec> platforms = <PlatformSpec>[];
      if (gapStart > 0.02) {
        platforms.add(
          PlatformSpec(
            x: 0.0,
            width: gapStart,
            suit: _suitFor(rng),
          ),
        );
      }
      if (gapEnd < 0.98) {
        platforms.add(
          PlatformSpec(
            x: gapEnd,
            width: 1.0 - gapEnd,
            suit: _suitFor(rng),
          ),
        );
      }

      rows.add(LevelRow(y: y, platforms: platforms));
    }

    // Sprinkle hazards on random platform tops.
    for (int i = 0; i < hazardCount; i++) {
      final int rowIdx = rng.nextInt(rows.length);
      final LevelRow row = rows[rowIdx];
      if (row.platforms.isEmpty) continue;
      final PlatformSpec p = row.platforms[rng.nextInt(row.platforms.length)];
      if (p.width < 0.12) continue;
      final double hw = 0.08 + rng.nextDouble() * 0.06;
      final double hx = p.x + rng.nextDouble() * (p.width - hw);
      final List<HazardSpec> hazards = List<HazardSpec>.from(row.hazards)
        ..add(HazardSpec(x: hx, width: hw, type: HazardType.thorns));
      rows[rowIdx] = LevelRow(
        y: row.y,
        platforms: row.platforms,
        hazards: hazards,
        coins: row.coins,
      );
    }

    // Devils float inside the gaps (mid-air hazards).
    for (int i = 0; i < devilCount; i++) {
      final int rowIdx = rng.nextInt(rows.length);
      final LevelRow row = rows[rowIdx];
      // Determine current gap on that row (space between platforms or edges).
      final _Gap g = _findGap(row);
      if (g.width < 0.12) continue;
      final double dw = 0.11;
      final double dx = g.start + rng.nextDouble() * (g.width - dw);
      final List<HazardSpec> hazards = List<HazardSpec>.from(row.hazards)
        ..add(HazardSpec(x: dx, width: dw, type: HazardType.devil));
      rows[rowIdx] = LevelRow(
        y: row.y,
        platforms: row.platforms,
        hazards: hazards,
        coins: row.coins,
      );
    }

    // Coins floating in the safe gap of random rows.
    for (int i = 0; i < coinCount; i++) {
      final int rowIdx = rng.nextInt(rows.length);
      final LevelRow row = rows[rowIdx];
      final _Gap g = _findGap(row);
      if (g.width < 0.1) continue;
      final double cx = g.start + rng.nextDouble() * (g.width - 0.08) + 0.04;
      final List<CoinSpec> coins = List<CoinSpec>.from(row.coins)
        ..add(CoinSpec(x: cx));
      rows[rowIdx] = LevelRow(
        y: row.y,
        platforms: row.platforms,
        hazards: row.hazards,
        coins: coins,
      );
    }

    return LevelConfig(
      number: clamped,
      fallSpeed: fallSpeed,
      length: length,
      rows: rows,
    );
  }

  static PlatformSuit _suitFor(Random rng) {
    const List<PlatformSuit> suits = <PlatformSuit>[
      PlatformSuit.hearts,
      PlatformSuit.diamonds,
      PlatformSuit.clubs,
      PlatformSuit.spades,
    ];
    return suits[rng.nextInt(suits.length)];
  }

  static _Gap _findGap(LevelRow row) {
    if (row.platforms.isEmpty) {
      return const _Gap(start: 0.0, end: 1.0);
    }
    double bestStart = 0.0;
    double bestEnd = 1.0;
    double bestWidth = 0.0;
    double cursor = 0.0;
    final List<PlatformSpec> sorted = List<PlatformSpec>.from(row.platforms)
      ..sort((PlatformSpec a, PlatformSpec b) => a.x.compareTo(b.x));
    for (final PlatformSpec p in sorted) {
      final double gw = p.x - cursor;
      if (gw > bestWidth) {
        bestWidth = gw;
        bestStart = cursor;
        bestEnd = p.x;
      }
      cursor = p.right;
    }
    final double tail = 1.0 - cursor;
    if (tail > bestWidth) {
      bestStart = cursor;
      bestEnd = 1.0;
    }
    return _Gap(start: bestStart, end: bestEnd);
  }
}

class _Gap {
  const _Gap({required this.start, required this.end});
  final double start;
  final double end;
  double get width => end - start;
}

String suitAsset(PlatformSuit suit) {
  switch (suit) {
    case PlatformSuit.hearts:
      return 'assets/hearts_platform.webp';
    case PlatformSuit.diamonds:
      return 'assets/bubna_platform.webp';
    case PlatformSuit.clubs:
      return 'assets/kresti_platform.webp';
    case PlatformSuit.spades:
      return 'assets/pika_platform.webp';
    case PlatformSuit.joker:
      return 'assets/chester_platform.webp';
  }
}
