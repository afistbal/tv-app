import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/mobad.dart';

class Admin extends StatefulWidget {
  const Admin({super.key});

  @override
  State<StatefulWidget> createState() {
    return _Admin();
  }
}

final GlobalKey key = GlobalKey();

class _Admin extends State<Admin> {
  InAppWebViewController? _controller;
  bool _ready = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (Platform.isAndroid && !didPop) {
            final url = await _controller?.getUrl();
            if (url?.path == null ||
                url!.path == '/' ||
                url.path.startsWith('/my-list') ||
                url.path.startsWith('/profile')) {
              if (context.mounted) {
                context.pop();
              }
              return;
            }

            if (await _controller?.canGoBack() == true) {
              _controller?.goBack();
            } else {
              if (context.mounted) {
                context.pop();
              }
            }
          }
        },
        child: SafeArea(
          child: InAppWebView(
            key: key,
            keepAlive: InAppWebViewKeepAlive(),
            initialSettings: InAppWebViewSettings(
              isInspectable: kDebugMode,
              allowFileAccessFromFileURLs: true,
              javaScriptEnabled: true,
              javaScriptCanOpenWindowsAutomatically: false,
              disableDefaultErrorPage: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
            ),
            initialUrlRequest: URLRequest(
              url: WebUri.uri(
                Uri.parse(
                  kDebugMode
                      ? 'http://192.168.1.30:5173/z'
                      : 'https://app.yogotv.com/z?s=A100APPANDROID&_token=${Global.sp.getString('token')}',
                ),
              ),
            ),
            onWebViewCreated: (controller) {
              _controller = controller;
              controller.addJavaScriptHandler(
                handlerName: 'currentUser',
                callback: (arguments) async {
                  return {
                    'uid': FirebaseAuth.instance.currentUser?.uid,
                    'name':
                        FirebaseAuth
                            .instance
                            .currentUser!
                            .providerData
                            .firstOrNull
                            ?.displayName ??
                        '',
                    'email': FirebaseAuth.instance.currentUser?.email ?? '',
                    'avatar': FirebaseAuth.instance.currentUser?.photoURL ?? '',
                    'anonymous':
                        FirebaseAuth.instance.currentUser?.isAnonymous ?? true,
                  };
                },
              );
              controller.addJavaScriptHandler(
                handlerName: 'logout',
                callback: (arguments) async {
                  await FirebaseAuth.instance.signOut();
                  await FirebaseAuth.instance.signInAnonymously();
                },
              );
              controller.addJavaScriptHandler(
                handlerName: 'emailSignIn',
                callback: (arguments) async {
                  Global.logger.i(arguments);
                  try {
                    final credential = EmailAuthProvider.credential(
                      email: arguments[0],
                      password: arguments[1],
                    );
                    if (arguments[2]) {
                      await FirebaseAuth.instance.currentUser
                          ?.linkWithCredential(credential);
                    } else {
                      await FirebaseAuth.instance.signInWithCredential(
                        credential,
                      );
                    }
                    return 'success';
                  } on FirebaseAuthException catch (e) {
                    Global.logger.d(e);
                    return e.code;
                  }
                },
              );
              controller.addJavaScriptHandler(
                handlerName: 'showAd',
                callback: (arguments) {
                  final completer = Completer();
                  rewardedAd((completed) {
                    completer.complete(completed);
                  });

                  return completer.future;
                },
              );
              controller.addJavaScriptHandler(
                handlerName: 'login',
                callback: (arguments) async {
                  try {
                    if (FirebaseAuth.instance.currentUser == null) {
                      await FirebaseAuth.instance.signInAnonymously();
                    }

                    controller.webStorage.localStorage.setItem(
                      key: 'uid',
                      value: FirebaseAuth.instance.currentUser!.uid,
                    );

                    Global.logger.d('${FirebaseAuth.instance.currentUser}');
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('❌ Oops! Something went wrong.'),
                        ),
                      );
                    }
                  }
                },
              );
              controller.addJavaScriptHandler(
                handlerName: 'initialized',
                callback: (arguments) async {
                  Global.elapsed('Startup time');

                  final locale = Platform.localeName.split('_').first;

                  debugPrint(locale);

                  return {"locale": locale};
                },
              );

              Global.logger.d('created');
            },
            onLoadStart: (controller, url) {
              Global.logger.d('start');
            },
            onLoadStop: (controller, url) async {
              if (_ready) {
                return;
              }
              _ready = true;
              Global.logger.d('ready');
            },
            onUpdateVisitedHistory: (controller, url, isReload) {
              if (url == null) {
                return;
              }
            },
            onReceivedError: (controller, request, error) async {
              var isForMainFrame = request.isForMainFrame ?? false;
              if (!isForMainFrame) {
                return;
              }
              Global.logger.d('${error.type}, ${error.description}');
              if (error.type == WebResourceErrorType.HOST_LOOKUP ||
                  error.type == WebResourceErrorType.NETWORK_CONNECTION_LOST ||
                  error.type == WebResourceErrorType.CANNOT_LOAD_FROM_NETWORK) {
                controller.loadFile(assetFilePath: "assets/web/error.html");
              }
            },
          ),
        ),
      ),
    );
  }
}
