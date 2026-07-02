import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'board_palette.dart';

/// Small utility WebView used by the white game menu to display
/// static legal pages (privacy policy, support). Deliberately kept
/// minimal — this is NOT the gray-flow WebView shell.
class BoardWebLeaf extends StatefulWidget {
  const BoardWebLeaf({super.key, required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<BoardWebLeaf> createState() => _BoardWebLeafState();
}

class _BoardWebLeafState extends State<BoardWebLeaf> {
  late final WebViewController _driver;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _driver = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(BoardPalette.background)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _busy = true),
          onPageFinished: (_) => setState(() => _busy = false),
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BoardPalette.background,
      appBar: AppBar(
        backgroundColor: BoardPalette.surface,
        foregroundColor: BoardPalette.accent,
        title: Text(
          widget.title,
          style: const TextStyle(
              fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: <Widget>[
          WebViewWidget(controller: _driver),
          if (_busy)
            const Center(
              child: CircularProgressIndicator(color: BoardPalette.accent),
            ),
        ],
      ),
    );
  }
}
