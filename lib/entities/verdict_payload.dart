/// Response envelope returned by the portal config endpoint.
/// `ok=true` + non-null `url` triggers the WebView shell path.
/// `ok=false` (or transport error) routes the user into the board game.
class VerdictPayload {
  const VerdictPayload({
    required this.allowed,
    this.targetUrl,
    this.reason,
    this.expiresAt,
  });

  factory VerdictPayload.parse(Map<String, dynamic> json) {
    return VerdictPayload(
      allowed: json['ok'] as bool? ?? false,
      targetUrl: json['url'] as String?,
      reason: json['message'] as String?,
      expiresAt: json['expires'] as int?,
    );
  }

  factory VerdictPayload.failure(String reason) =>
      VerdictPayload(allowed: false, reason: reason);

  /// True if the backend approves the WebView (paid install).
  final bool allowed;
  final String? targetUrl;
  final String? reason;
  final int? expiresAt;
}
