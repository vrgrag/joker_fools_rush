import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'boot/root_app.dart';
import 'gate/alert_courier.dart';
import 'gate/attribution_hub.dart';
import 'net/agent_client.dart';
import 'net/net_sensor.dart';
import 'net/verdict_gateway.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase + AppCheck are optional during pre-config bring-up.
  try {
    await Firebase.initializeApp();
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
    );
  } catch (_) {
    // No google-services.json yet — degrade to no-op.
  }

  // Only portrait initially; the PortalStage temporarily allows landscape
  // while its loading art is on screen, then locks portrait again.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await agentClient.prepare();

  final NetSensor sensor = NetSensor();
  final AttributionHub attribution = AttributionHub();
  final VerdictGateway gateway = VerdictGateway();
  final AlertCourier courier = AlertCourier();

  runApp(RushRootApp(
    sensor: sensor,
    attribution: attribution,
    gateway: gateway,
    courier: courier,
  ));
}
