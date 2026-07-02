import 'legal_endpoints.dart';
import 'beacon_seeds.dart';
import 'portal_seeds.dart';

/// Static facade over app identity + resolved sensitive values.
/// All getters resolve via cryptic byte arrays so plaintext strings
/// never appear in the compiled binary.
class Identity {
  const Identity._();

  /// Play Store package name / applicationId.
  static const String bundleId = 'com.foolgold.foolsrush';

  /// Same as bundleId on Android — kept separate for parity with iOS builds.
  static const String storeId = 'com.foolgold.foolsrush';

  /// User-visible label used inside notifications and analytics logs.
  /// Written in PascalCase, no spaces (used inside the User-Agent suffix).
  static const String appName = 'FoolsRush';

  /// Analytics app id — reserved for iOS App Store numeric id.
  static const String analyticsAppId = '';

  /// Resolves the full config endpoint URL (host + path).
  static String get portalEndpoint => unlockPortalEndpoint();

  /// Resolves the AppsFlyer developer key from the beacon seeds.
  static String get analyticsKey => unlockAnalyticsKey();

  /// Firebase project number (sender id).
  static String get messagingProject => unlockMessagingProject();

  /// Static legal URLs — displayed in the white game menu.
  static String get privacyPolicyUrl => privacyPolicyPageUrl;
  static String get supportUrl => supportPageUrl;

  /// Delay before the notification promo is offered again if user tapped Skip.
  static const int notificationDeferSeconds = 259200; // 3 days

  /// Delay before we re-request AppsFlyer conversion data through GCD
  /// when the first callback reports af_status == "Organic".
  static const int gcdRetrySeconds = 5;
}
