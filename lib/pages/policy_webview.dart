import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';
import 'package:yogotv/components/android_toolbar.dart';

class PolicyWebView extends StatefulWidget {
  const PolicyWebView({super.key, required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<PolicyWebView> createState() => _PolicyWebViewState();
}

class _PolicyWebViewState extends State<PolicyWebView> {
  int _progress = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AndroidToolbar(title: widget.title, onBack: context.pop),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: InAppWebView(
                      initialUrlRequest: URLRequest(
                        url: WebUri.uri(Uri.parse(widget.url)),
                      ),
                      initialSettings: InAppWebViewSettings(
                        isInspectable: kDebugMode,
                        javaScriptEnabled: true,
                        disableDefaultErrorPage: true,
                      ),
                      onProgressChanged: (_, progress) {
                        if (mounted) {
                          setState(() => _progress = progress);
                        }
                      },
                    ),
                  ),
                  if (_progress < 100)
                    const PositionedDirectional(
                      top: 0,
                      start: 0,
                      end: 0,
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        color: Color(0xffff3d5d),
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
