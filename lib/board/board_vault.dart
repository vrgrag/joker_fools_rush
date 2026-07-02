import 'package:shared_preferences/shared_preferences.dart';

/// Persistent progress store for the white game.
/// Uses distinct keys ('br_*') so it never collides with gray-flow keys.
class BoardVault {
  BoardVault._();
  static final BoardVault instance = BoardVault._();

  static const String _kUnlocked = 'br_unlocked_stage';
  static const String _kStarsPrefix = 'br_stars_';
  static const String _kJesterCoins = 'br_jester_coins';

  SharedPreferences? _prefs;

  Future<void> warmUp() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  int get unlockedLevels => _prefs?.getInt(_kUnlocked) ?? 1;

  int get jesterCoins => _prefs?.getInt(_kJesterCoins) ?? 0;

  int starsFor(int level) => _prefs?.getInt('$_kStarsPrefix$level') ?? 0;

  Future<void> completeStage(int level, int stars, int coins) async {
    await warmUp();
    final int prev = starsFor(level);
    if (stars > prev) {
      await _prefs!.setInt('$_kStarsPrefix$level', stars);
    }
    final int nextUnlocked = level + 1;
    if (nextUnlocked > unlockedLevels) {
      await _prefs!.setInt(_kUnlocked, nextUnlocked);
    }
    await _prefs!.setInt(_kJesterCoins, jesterCoins + coins);
  }

  Future<void> wipe() async {
    await warmUp();
    await _prefs!.clear();
  }
}
