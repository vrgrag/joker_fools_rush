import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Connectivity probe.
/// Applies gray-flow pitfall fixes:
///   - Whitelist VPN + Bluetooth + Ethernet + Other as "online"
///   - DNS lookup timeout raised to 7s (VPN tunnels can be slow)
///   - Consumer of `statusStream` should debounce for 700ms.
class NetSensor {
  NetSensor();

  final Connectivity _plugin = Connectivity();

  /// Values that count as "connected" for the purposes of gray-flow routing.
  /// Notice that we treat VPN as a real interface — a very common oversight.
  static const Set<ConnectivityResult> _activeInterfaces =
      <ConnectivityResult>{
    ConnectivityResult.wifi,
    ConnectivityResult.mobile,
    ConnectivityResult.ethernet,
    ConnectivityResult.vpn,
    ConnectivityResult.bluetooth,
    ConnectivityResult.other,
  };

  /// Two-step probe: interface active AND DNS reachable.
  /// Returns false only on true offline; VPN tunnels resolve properly.
  Future<bool> isReachable({String host = 'cloudflare.com'}) async {
    try {
      final List<ConnectivityResult> reports =
          await _plugin.checkConnectivity();
      if (!reports.any(_activeInterfaces.contains)) return false;

      final List<InternetAddress> lookup = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 7));
      return lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  Stream<List<ConnectivityResult>> get statusStream =>
      _plugin.onConnectivityChanged;
}
