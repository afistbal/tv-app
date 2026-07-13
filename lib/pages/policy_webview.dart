import 'dart:io';

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
  InAppWebViewController? _controller;
  int _progress = 0;

  Future<void> _back() async {
    if (!kIsWeb &&
        Platform.isAndroid &&
        await _controller?.canGoBack() == true) {
      await _controller?.goBack();
      return;
    }
    if (mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AndroidToolbar(title: widget.title, onBack: _back),
            Expanded(
              child: Stack(
                children: [
                  InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri.uri(Uri.parse(widget.url)),
                    ),
                    initialSettings: InAppWebViewSettings(
                      isInspectable: kDebugMode,
                      javaScriptEnabled: true,
                      disableDefaultErrorPage: true,
                    ),
                    onWebViewCreated: (controller) {
                      _controller = controller;
                    },
                    onProgressChanged: (_, progress) {
                      if (mounted) {
                        setState(() => _progress = progress);
                      }
                    },
                  ),
                  if (_progress < 100)
                    const LinearProgressIndicator(
                      minHeight: 2,
                      color: Color(0xffff3d5d),
                      backgroundColor: Colors.transparent,
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
