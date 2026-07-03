import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../gate/alert_courier.dart';
import '../net/agent_client.dart';
import '../net/net_sensor.dart';
import 'offline_notice.dart';

/// Full-screen WebView shell.
///
/// Applied pitfall fixes (see gray_part_pitfalls.md):
///   #3  700ms debounce before routing to OfflineNotice on connectivity drop.
///   #4  On DNS/disconnect errorCode -105/-106/-21 → immediate spinner cover +
///       skip redundant DNS probe.
///   webview_keyboard.mdc — `adjustResize` in manifest + `resizeToAvoidBottomInset:false`
///       here + JS injection with `behavior:'auto'` and single 350ms setTimeout.
///   custom_screens.md — apply left/right viewPadding in landscape for
///       devices with a camera notch on the side.
class WebPortal extends StatefulWidget {
  const WebPortal({
    super.key,
    required this.targetUrl,
    required this.sensor,
    required this.courier,
  });

  final String targetUrl;
  final NetSensor sensor;
  final AlertCourier courier;

  @override
  State<WebPortal> createState() => _WebPortalState();
}

class _WebPortalState extends State<WebPortal>
    with WidgetsBindingObserver {
  static const MethodChannel _nativeChannel =
      MethodChannel('com.foolgold.foolsrush/webview_native');

  late final WebViewController _driver;
  bool _busy = true;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _offlineDebounce;
  Timer? _chromeSettingsTimer;
  bool _chromeSettingsApplied = false;
  bool _showingOffline = false;
  String? _lastMainUrl;
  int _redirectRetries = 0;

  void _applyImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _applyImmersive();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _applyImmersive();

    _driver = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(agentClient.deviceAgent)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _busy = true);
          if (!_chromeSettingsApplied) _scheduleChromeLikeSettings();
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _busy = false);
          _redirectRetries = 0;
          _injectSafeAreaScrub();
          _injectKeyboardFocus();
        },
        onWebResourceError: (WebResourceError err) {
          if (err.isForMainFrame != true) return;
          final String desc = err.description.toLowerCase();

          final bool tooManyRedirects =
              desc.contains('too_many_redirects') ||
                  desc.contains('too many redirects') ||
                  err.errorCode == -1007 ||
                  err.errorCode == -9;
          if (tooManyRedirects &&
              _lastMainUrl != null &&
              _redirectRetries < 3) {
            _redirectRetries++;
            _driver.loadRequest(Uri.parse(_lastMainUrl!));
            return;
          }

          // Pitfall #4 — cover the native error page immediately.
          if (mounted) setState(() => _busy = true);

          final bool dnsOrDisconnect =
              desc.contains('name_not_resolved') ||
                  desc.contains('err_name_not_resolved') ||
                  desc.contains('internet_disconnected') ||
                  desc.contains('network_changed') ||
                  err.errorCode == -105 ||
                  err.errorCode == -106 ||
                  err.errorCode == -21;

          if (dnsOrDisconnect) {
            _routeToOfflineNow();
          } else {
            _routeToOfflineIfDown();
          }
        },
        onNavigationRequest: (NavigationRequest req) {
          final Uri? uri = Uri.tryParse(req.url);
          if (uri == null) return NavigationDecision.prevent;
          final String scheme = uri.scheme;
          if (scheme == 'http' ||
              scheme == 'https' ||
              scheme == 'about' ||
              scheme == 'data' ||
              scheme == 'blob') {
            if (req.isMainFrame) _lastMainUrl = req.url;
            return NavigationDecision.navigate;
          }
          _launchExternal(uri);
          return NavigationDecision.prevent;
        },
      ))
      ..enableZoom(false);

    _wireAndroid();
    _driver.loadRequest(Uri.parse(widget.targetUrl));
    _scheduleChromeLikeSettings();

    widget.courier.onWarmUrl = (String url) {
      if (mounted) _driver.loadRequest(Uri.parse(url));
    };

    // Debounce the connectivity stream — pitfall #3.
    _connSub = widget.sensor.statusStream.listen((List<ConnectivityResult> r) {
      final bool allNone = r.every((ConnectivityResult v) =>
          v == ConnectivityResult.none);
      if (!allNone) {
        _offlineDebounce?.cancel();
        return;
      }
      _offlineDebounce?.cancel();
      _offlineDebounce = Timer(const Duration(milliseconds: 700), () {
        _routeToOfflineNow();
      });
    });
  }

  Future<void> _routeToOfflineIfDown() async {
    if (_showingOffline) return;
    final bool online = await widget.sensor.isReachable();
    if (online || !mounted) return;
    _routeToOfflineNow();
  }

  void _routeToOfflineNow() {
    if (_showingOffline || !mounted) return;
    _showingOffline = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => OfflineNotice(
          onRetry: (BuildContext ctx) => Navigator.of(ctx).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => WebPortal(
                targetUrl: widget.targetUrl,
                sensor: widget.sensor,
                courier: widget.courier,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Repeatedly calls the native side to set `useWideViewPort=true` and
  /// `loadWithOverviewMode=true` on the WebView platform view.
  ///
  /// The WebView is created asynchronously by the platform view, so we
  /// poll every 200 ms until at least one WebView is configured, or we've
  /// tried 25 times (~5 seconds).
  void _scheduleChromeLikeSettings() {
    if (!Platform.isAndroid) return;
    int attempts = 0;
    _chromeSettingsTimer?.cancel();
    _chromeSettingsTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (Timer t) async {
        attempts++;
        if (!mounted || attempts > 25 || _chromeSettingsApplied) {
          t.cancel();
          return;
        }
        try {
          final int? count = await _nativeChannel
              .invokeMethod<int>('applyChromeLikeSettings');
          if ((count ?? 0) > 0) {
            _chromeSettingsApplied = true;
            t.cancel();
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[WebPortal] native settings error: $e');
        }
      },
    );
  }

  void _wireAndroid() {
    if (!Platform.isAndroid) return;
    if (_driver.platform is! AndroidWebViewController) return;
    final AndroidWebViewController plat =
        _driver.platform as AndroidWebViewController;
    plat.setMediaPlaybackRequiresUserGesture(false);
    plat.setOnShowFileSelector(_pickFiles);
    final AndroidWebViewCookieManager cookies = AndroidWebViewCookieManager(
      AndroidWebViewCookieManagerCreationParams
          .fromPlatformWebViewCookieManagerCreationParams(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
    );
    cookies.setAcceptThirdPartyCookies(plat, true);
  }

  Future<List<String>> _pickFiles(FileSelectorParams params) async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: params.mode == FileSelectorMode.openMultiple,
        type: FileType.any,
      );
      if (result != null) {
        return result.files
            .where((PlatformFile f) => f.path != null)
            .map((PlatformFile f) => Uri.file(f.path!).toString())
            .toList();
      }
    } catch (_) {}
    return <String>[];
  }

  Future<void> _launchExternal(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _injectKeyboardFocus() {
    _driver.runJavaScript(r'''
(function(){
  if (window.__fyKbArmed) return;
  window.__fyKbArmed = true;

  function isField(el){
    if (!el) return false;
    var t = el.tagName;
    return t === 'INPUT' || t === 'TEXTAREA' || el.isContentEditable === true;
  }

  function bringUp(){
    var el = document.activeElement;
    if (!isField(el)) return;
    var vv = window.visualViewport;
    if (vv) {
      var r = el.getBoundingClientRect();
      var bottom = vv.offsetTop + vv.height;
      if (r.bottom > bottom - 20 || r.top < vv.offsetTop) {
        el.scrollIntoView({ behavior: 'auto', block: 'nearest' });
      }
    } else {
      el.scrollIntoView({ behavior: 'auto', block: 'nearest' });
    }
  }

  document.addEventListener('focusin', function(ev){
    if (isField(ev.target)) setTimeout(bringUp, 350);
  });

  if (window.visualViewport) {
    var last = window.visualViewport.height;
    window.visualViewport.addEventListener('resize', function(){
      var h = window.visualViewport.height;
      if (h < last) setTimeout(bringUp, 120);
      last = h;
    });
  }
})();
''');
  }

  void _injectSafeAreaScrub() {
    _driver.runJavaScript(r'''
(function(){
  if (window.__fySaArm) return;
  window.__fySaArm = true;

  var STYLE_ID = '__fy_sa';
  var CSS =
    ':root{'+
    '--safe-area-inset-top:0px!important;'+
    '--safe-area-inset-right:0px!important;'+
    '--safe-area-inset-bottom:0px!important;'+
    '--safe-area-inset-left:0px!important;'+
    '--sat:0px!important;--sar:0px!important;'+
    '--sab:0px!important;--sal:0px!important;'+
    '--safe-top:0px!important;--safe-right:0px!important;'+
    '--safe-bottom:0px!important;--safe-left:0px!important;'+
    '}'+
    'html,body,#app,#root,#__next,#__nuxt,#__layout{'+
    'padding-top:0!important;padding-left:0!important;'+
    'padding-right:0!important;margin-top:0!important;}';

  function kbOpen(){
    if (!window.visualViewport) return false;
    return window.visualViewport.height < window.innerHeight * 0.75;
  }

  function apply(){
    if (kbOpen()) return;
    var head = document.head || document.documentElement;
    if (!head) return;
    var m = document.querySelector('meta[name="viewport"]');
    if (m && !/viewport-fit\s*=\s*contain/i.test(m.getAttribute('content') || '')) {
      var c = (m.getAttribute('content') || '')
        .replace(/,?\s*viewport-fit\s*=\s*\w+/ig,'').trim();
      m.setAttribute('content', c + (c ? ', ' : '') + 'viewport-fit=contain');
    }
    var s = document.getElementById(STYLE_ID);
    if (!s) {
      s = document.createElement('style');
      s.id = STYLE_ID;
      head.appendChild(s);
    }
    if (s.textContent !== CSS) s.textContent = CSS;
  }

  apply();

  ['pushState','replaceState'].forEach(function(fn){
    var orig = history[fn];
    history[fn] = function(){
      var r = orig.apply(this, arguments);
      setTimeout(apply, 80);
      setTimeout(apply, 380);
      return r;
    };
  });
  window.addEventListener('popstate', function(){ setTimeout(apply, 80); });
  setInterval(apply, 2500);
})();
''');
  }

  Future<bool> _onBack() async {
    if (await _driver.canGoBack()) {
      await _driver.goBack();
    }
    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connSub?.cancel();
    _offlineDebounce?.cancel();
    _chromeSettingsTimer?.cancel();
    widget.courier.onWarmUrl = null;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets insets = MediaQuery.of(context).viewPadding;
    final bool landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    // Landscape safe-zone: apply left/right for camera notch on side.
    // Portrait: apply top for status bar area.
    final EdgeInsets pad = landscape
        ? EdgeInsets.only(left: insets.left, right: insets.right)
        : EdgeInsets.only(top: insets.top);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) async {
        if (!didPop) await _onBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false, // required for the keyboard fix
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Padding(
              padding: pad,
              child: WebViewWidget(controller: _driver),
            ),
            if (_busy)
              Container(
                color: Colors.black.withValues(alpha: 0.55),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFFFFC107)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
