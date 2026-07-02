import 'package:flutter/material.dart';

import '../board/board_palette.dart';
import '../gate/alert_courier.dart';
import '../gate/attribution_hub.dart';
import '../net/net_sensor.dart';
import '../net/verdict_gateway.dart';
import '../pages/portal_stage.dart';

class RushRootApp extends StatelessWidget {
  const RushRootApp({
    super.key,
    required this.sensor,
    required this.attribution,
    required this.gateway,
    required this.courier,
  });

  final NetSensor sensor;
  final AttributionHub attribution;
  final VerdictGateway gateway;
  final AlertCourier courier;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Fool's Rush",
      debugShowCheckedModeBanner: false,
      theme: BoardPalette.composeDarkTheme(),
      home: PortalStage(
        sensor: sensor,
        attribution: attribution,
        gateway: gateway,
        courier: courier,
      ),
    );
  }
}
