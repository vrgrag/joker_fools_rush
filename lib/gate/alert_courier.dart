import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../net/agent_client.dart';
import '../vault/local_vault.dart';

// ============================================================
// ALERT COURIER — Firebase Messaging + local display
// ============================================================
// Semantics (per TZ):
//   - Cold-start tap (app was killed): getInitialMessage() → SAVE the URL
//   - Warm background tap:              onMessageOpenedApp → callback only
//   - Foreground receive:               show local notification → tap → callback
//
// Icon: @drawable/ic_notification — a flame vector (matches game theme).
// Channel id 'ff_channel' — matches AndroidManifest meta-data.
// ============================================================

@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage message) async {
  // Intentionally minimal — the tap wakes the app via onMessageOpenedApp
  // or getInitialMessage(), both of which run inside the main isolate.
}

class AlertCourier {
  AlertCourier();

  static const String _channelId = 'ff_channel';
  static const String _channelName = 'Fool\'s Rush Alerts';
  static const String _iconRes = '@drawable/ic_notification';

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  FirebaseMessaging? _fcm;
  String? _token;
  bool _booted = false;

  /// Called when a warm push tap should be reflected into the visible UI.
  /// The WebPortal registers itself here so incoming URLs live-navigate.
  void Function(String url)? onWarmUrl;

  /// FCM token was rotated — the splash re-POSTs so the backend gets it.
  void Function(String freshToken)? onTokenRotated;

  String? get currentToken => _token;

  Future<void> boot() async {
    if (_booted) return;
    try {
      await Firebase.initializeApp();
      _fcm = FirebaseMessaging.instance;

      FirebaseMessaging.onBackgroundMessage(_bgHandler);

      await _wireLocal();

      _token = await _fcm!.getToken();
      _fcm!.onTokenRefresh.listen((String t) {
        _token = t;
        onTokenRotated?.call(t);
      });

      FirebaseMessaging.onMessage.listen(_showForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_openedFromBg);

      final RemoteMessage? initial = await _fcm!.getInitialMessage();
      if (initial != null) {
        _openedFromCold(initial);
      }

      _booted = true;
    } catch (_) {
      // Firebase not configured yet — degrade to silent no-op.
      _booted = false;
    }
  }

  Future<bool> askPermission() async {
    if (_fcm == null) return false;
    try {
      final NotificationSettings s = await _fcm!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final bool granted =
          s.authorizationStatus == AuthorizationStatus.authorized ||
              s.authorizationStatus == AuthorizationStatus.provisional;
      await LocalVault.instance.markNotifGranted(granted);
      if (!granted &&
          s.authorizationStatus == AuthorizationStatus.denied) {
        // OS-level "denied" → dialog cannot be shown again on Android 13+.
        await LocalVault.instance.markNotifOsBlocked();
      }
      return granted;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------------
  //  internal
  // ------------------------------------------------------------------

  Future<void> _wireLocal() async {
    const AndroidInitializationSettings android =
        AndroidInitializationSettings(_iconRes);
    const DarwinInitializationSettings ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _local.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (NotificationResponse resp) {
        if (resp.payload == null) return;
        try {
          final Map<String, dynamic> data =
              jsonDecode(resp.payload!) as Map<String, dynamic>;
          final String? url = data['url'] as String?;
          if (url != null && url.isNotEmpty) onWarmUrl?.call(url);
        } catch (_) {}
      },
    );

    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
          _local.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Delivery channel for Fool\'s Rush push messages',
          importance: Importance.high,
        ),
      );
    }
  }

  Future<void> _showForeground(RemoteMessage m) async {
    final RemoteNotification? notif = m.notification;
    if (notif == null) return;
    if (!Platform.isAndroid) return;

    AndroidNotificationDetails details;
    final String? big = m.notification?.android?.imageUrl;
    if (big != null && big.isNotEmpty) {
      final Uint8List? picture = await _grabImage(big);
      if (picture != null) {
        details = AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: _iconRes,
          styleInformation: BigPictureStyleInformation(
            ByteArrayAndroidBitmap(picture),
            largeIcon:
                const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          ),
        );
      } else {
        details = const AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: _iconRes,
        );
      }
    } else {
      details = const AndroidNotificationDetails(
        _channelId,
        _channelName,
        importance: Importance.high,
        priority: Priority.high,
        icon: _iconRes,
      );
    }

    final String? payload =
        m.data.isNotEmpty ? jsonEncode(m.data) : null;
    await _local.show(
      notif.hashCode,
      notif.title,
      notif.body,
      NotificationDetails(android: details),
      payload: payload,
    );
  }

  void _openedFromBg(RemoteMessage m) {
    final String? url = m.data['url'] as String?;
    if (url != null && url.isNotEmpty) onWarmUrl?.call(url);
  }

  void _openedFromCold(RemoteMessage m) {
    final String? url = m.data['url'] as String?;
    if (url != null && url.isNotEmpty) {
      LocalVault.instance.pushPushUrl(url);
    }
  }

  Future<Uint8List?> _grabImage(String url) async {
    try {
      final response =
          await agentClient.get(Uri.parse(url)).timeout(
                const Duration(seconds: 10),
              );
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {}
    return null;
  }
}
