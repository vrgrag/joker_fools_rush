import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

import '../codec/cryptic.dart';
import '../env/identity.dart';

// ============================================================
// AGENT CLIENT — real device User-Agent for outgoing HTTP
// ============================================================
// The default Dart User-Agent is easy to fingerprint. We compose a
// UA that mimics the Android WebView Chrome and, because this game
// uses a Joker slot-theme, append `appid/... appname/...` to the very
// end (per gray_user_agent.mdc).
//
// The exact same string must be set on the WebViewController so that
// analytics on the partner side see consistent traffic.
// ============================================================

// Encoded Chrome/WebKit fragments so the version numbers don't grep out
// as plain "132.0..." strings inside the APK.
const List<int> _kChromeVer = <int>[
  0x8c, 0x9c, 0xae, 0x76, 0x59, 0x40, 0xe4, 0xc9, 0xe6, 0x18, 0x1a, 0x1a,
  0x7f, 0xce,
];
const List<int> _kWebKitVer = <int>[
  0x88, 0x9c, 0xab, 0x76, 0x5a, 0x58,
];

class AgentClient extends http.BaseClient {
  AgentClient();

  final http.Client _pipe = http.Client();
  String _deviceAgent = 'Mozilla/5.0';
  bool _ready = false;

  /// Composes the User-Agent from actual device info.
  /// Must be awaited once during app startup, before any other request.
  Future<void> prepare() async {
    if (_ready) return;
    _ready = true;

    final String chromeVer =
        reveal(_kChromeVer).isEmpty ? '132.0.6834.163' : reveal(_kChromeVer);
    final String webkitVer =
        reveal(_kWebKitVer).isEmpty ? '537.36' : reveal(_kWebKitVer);

    try {
      final DeviceInfoPlugin info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final AndroidDeviceInfo a = await info.androidInfo;
        final int sdk = a.version.sdkInt;
        final String brand = a.brand;
        final String model = a.model;
        final String build = a.display.isNotEmpty ? a.display : a.id;
        _deviceAgent = 'Mozilla/5.0 (Linux; Android $sdk; $brand $model '
            'Build/$build) AppleWebKit/$webkitVer (KHTML, like Gecko) '
            'Chrome/$chromeVer Mobile Safari/$webkitVer';
      } else {
        final IosDeviceInfo i = await info.iosInfo;
        final String ver = i.systemVersion.replaceAll('.', '_');
        _deviceAgent = 'Mozilla/5.0 (iPhone; CPU iPhone OS $ver like Mac OS X)'
            ' AppleWebKit/$webkitVer (KHTML, like Gecko) '
            'Version/${i.systemVersion} Mobile/15E148 Safari/$webkitVer';
      }
    } catch (_) {
      // Sensible fallback if plugin fails.
      _deviceAgent = 'Mozilla/5.0 (Linux; Android 14; Pixel 8 '
          'Build/UP1A.231005.007) AppleWebKit/$webkitVer (KHTML, like Gecko) '
          'Chrome/$chromeVer Mobile Safari/$webkitVer';
    }

    // Joker theme = slot theme → append appid/appname per the rule.
    _deviceAgent =
        '$_deviceAgent appid/${Identity.bundleId} appname/${Identity.appName}';
  }

  /// Publicly readable UA — also set on `WebViewController.setUserAgent`.
  String get deviceAgent => _deviceAgent;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.putIfAbsent('User-Agent', () => _deviceAgent);
    return _pipe.send(request);
  }

  @override
  void close() => _pipe.close();
}

/// Global singleton used by every service that talks HTTP.
final AgentClient agentClient = AgentClient();
