import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../entities/launch_stage.dart';

/// Persistent storage facade.
/// Non-sensitive flags live in SharedPreferences with obfuscated keys.
/// URLs (config + push) live in FlutterSecureStorage.
class LocalVault {
  LocalVault._();
  static final LocalVault instance = LocalVault._();

  // Deliberately opaque keys — no plaintext 'app_mode', 'push_url' etc.
  static const String _kStage = 'st_v3';
  static const String _kExpires = 'exp_v3';
  static const String _kSkipUntil = 'nx_skip';
  static const String _kGranted = 'nx_ok';
  static const String _kOsDenied = 'nx_blocked';
  static const String _kSavedUrlSecure = 'q_u';
  static const String _kPushUrlSecure = 'q_p';

  SharedPreferences? _prefs;
  final FlutterSecureStorage _bag = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> awaken() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // -- launch stage --

  LaunchStage readStage() => LaunchStage.decode(_prefs?.getString(_kStage));

  Future<void> writeStage(LaunchStage stage) async {
    await awaken();
    await _prefs!.setString(_kStage, stage.encode());
  }

  // -- saved config URL (secure) --

  Future<String?> pullSavedUrl() async {
    try {
      return await _bag.read(key: _kSavedUrlSecure);
    } catch (_) {
      return null;
    }
  }

  Future<void> pushSavedUrl(String url) async {
    try {
      await _bag.write(key: _kSavedUrlSecure, value: url);
    } catch (_) {}
  }

  int? readExpiryTs() => _prefs?.getInt(_kExpires);

  Future<void> writeExpiryTs(int ts) async {
    await awaken();
    await _prefs!.setInt(_kExpires, ts);
  }

  bool isExpired() {
    final int? ts = readExpiryTs();
    if (ts == null) return true;
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= ts;
  }

  // -- push permission flags --

  bool notifGranted() => _prefs?.getBool(_kGranted) ?? false;

  Future<void> markNotifGranted(bool value) async {
    await awaken();
    await _prefs!.setBool(_kGranted, value);
  }

  bool notifOsBlocked() => _prefs?.getBool(_kOsDenied) ?? false;

  Future<void> markNotifOsBlocked() async {
    await awaken();
    await _prefs!.setBool(_kOsDenied, true);
  }

  int? readSkipUntil() => _prefs?.getInt(_kSkipUntil);

  Future<void> writeSkipUntil(int ts) async {
    await awaken();
    await _prefs!.setInt(_kSkipUntil, ts);
  }

  /// Should the notification-permission screen be presented?
  /// - No, if already granted
  /// - No, if the OS denied it (dialog can no longer be raised)
  /// - Yes, if never asked, or the skip window has elapsed
  bool shouldPromptForNotifications() {
    if (notifGranted()) return false;
    if (notifOsBlocked()) return false;
    final int? until = readSkipUntil();
    if (until == null) return true;
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= until;
  }

  // -- one-shot push URL (secure) --

  Future<String?> pullPushUrl() async {
    try {
      return await _bag.read(key: _kPushUrlSecure);
    } catch (_) {
      return null;
    }
  }

  Future<void> pushPushUrl(String? url) async {
    try {
      if (url == null) {
        await _bag.delete(key: _kPushUrlSecure);
      } else {
        await _bag.write(key: _kPushUrlSecure, value: url);
      }
    } catch (_) {}
  }

  /// Reads and immediately deletes the pending push URL.
  Future<String?> consumePushUrl() async {
    final String? url = await pullPushUrl();
    if (url != null) {
      await pushPushUrl(null);
    }
    return url;
  }
}
