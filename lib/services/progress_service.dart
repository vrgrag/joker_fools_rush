import 'package:shared_preferences/shared_preferences.dart';

class ProgressService {
  ProgressService._();
  static final ProgressService instance = ProgressService._();

  static const String _kUnlocked = 'unlocked_levels';
  static const String _kStarsPrefix = 'level_stars_';
  static const String _kCoins = 'total_coins';

  SharedPreferences? _prefs;

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  int get unlockedLevels => _prefs?.getInt(_kUnlocked) ?? 1;

  int get totalCoins => _prefs?.getInt(_kCoins) ?? 0;

  int starsFor(int level) => _prefs?.getInt('$_kStarsPrefix$level') ?? 0;

  Future<void> completeLevel(int level, int stars, int coins) async {
    await load();
    final int prev = starsFor(level);
    if (stars > prev) {
      await _prefs!.setInt('$_kStarsPrefix$level', stars);
    }
    final int nextUnlocked = level + 1;
    if (nextUnlocked > unlockedLevels) {
      await _prefs!.setInt(_kUnlocked, nextUnlocked);
    }
    await _prefs!.setInt(_kCoins, totalCoins + coins);
  }

  Future<void> resetProgress() async {
    await load();
    await _prefs!.clear();
  }
}
