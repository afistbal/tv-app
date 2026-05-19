import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';

class Airwallex extends StatefulWidget {
  final int product;
  const Airwallex({super.key, required this.product});

  @override
  State<StatefulWidget> createState() {
    return _Airwallex();
  }
}

class _Airwallex extends State<Airwallex> {
  final channel = MethodChannel('yogotv.com/channel');
  late final InAppWebViewController? _controller;
  final InAppWebViewSettings _settings = InAppWebViewSettings(
    isInspectable: kDebugMode,
  );
  int _progress = 0;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t.checkout)),
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (Platform.isAndroid && !didPop) {
            if (await _controller!.canGoBack()) {
              _controller.goBack();
            } else {
              if (context.mounted) {
                context.pop();
              }
            }
          }
        },
        child: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(
                  "${kDebugMode ? 'http://192.168.1.30:5173' : 'https://app.yogotv.com'}/airwallex/${widget.product}?s=A100APPANDROID&_token=${Global.sp.getString('token')}",
                ),
              ),
              initialSettings: _settings,
              onWebViewCreated: (controller) {
                _controller = controller;
                _controller!.addJavaScriptHandler(
                  handlerName: 'back',
                  callback: (List<dynamic> arguments) {
                    context.pop(arguments.isEmpty ? null : arguments[0]);
                  },
                );
              },
              onProgressChanged: (controller, progress) {
                setState(() {
                  _progress = progress;
                });
              },
            ),
            if (_progress < 100)
              LinearProgressIndicator(value: _progress / 100, minHeight: 2),
          ],
        ),
      ),
    );
  }
}
