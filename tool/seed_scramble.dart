// Tool: prints encoded byte arrays for sensitive strings.
// Run: dart run tool/seed_scramble.dart
import '../lib/codec/cryptic.dart';

void main() {
  const Map<String, String> secrets = <String, String>{
    'kConfigHost':      'https://foolsrussh.com',
    'kConfigPath':      '/config.php',
    'kGcdHost':         'https://gcdsdk.appsflyer.com',
    'kGcdPath':         '/install_data/v4.0/',
    'kChromeVer':       '132.0.6834.163',
    'kWebKitVer':       '537.36',
    'kAnalyticsKey':    'Yewbh5LNiMRUtJTmegCxCA',
    'kMessagingProject':'52819805504',
  };

  secrets.forEach((String label, String value) {
    final List<int> bytes = scramble(value);
    final String arr = bytes.map((int b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ');
    print('// $label = "$value"');
    print('const List<int> $label = <int>[$arr];');
    print('');
  });
}
