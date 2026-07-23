import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:yogotv/adjust_tracking.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/components/android_toolbar.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/main.dart';
import 'package:yogotv/pages/policy_webview.dart';
import 'package:yogotv/states/user.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<StatefulWidget> createState() {
    return _Login();
  }
}

class _Login extends State<Login> {
  static const String _googleWebClientId =
      '1060307128443-qf4266aj8kfscpf3nv9g8lvkseiip75v.apps.googleusercontent.com';

  @override
  initState() {
    super.initState();
    Global.blockAd();
  }

  @override
  dispose() {
    Global.allowAd();
    super.dispose();
  }

  _onGoogleSign() async {
    final cancel = Global.loading();
    try {
      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await GoogleSignIn(
        clientId: kIsWeb ? _googleWebClientId : null,
        scopes: ['email', 'profile'],
      ).signIn();
      if (googleUser == null) {
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      if (googleAuth.accessToken == null && googleAuth.idToken == null) {
        Global.error(t.login_failed);
        return;
      }

      if (mounted) {
        final signed = await Global.loginWithGoogle(
          context,
          email: googleUser.email,
          name: googleUser.displayName ?? '',
          googleId: googleUser.id,
          avatarUrl: googleUser.photoUrl ?? '',
        );
        if (signed && mounted) {
          context.pop(true);
        } else if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      if (e.toString().contains('popup_closed')) {
        return;
      }
      Global.logger.d(e.toString());
      Global.error(t.login_failed);
    } finally {
      cancel();
    }
  }

  _onAppleSign() async {
    if (kIsWeb || Global.webPreview) {
      Global.info('Please test Apple login in the iOS app.');
      return;
    }
    final cancel = Global.loading();
    try {
      final provider = AppleAuthProvider();
      provider.addScope('email');
      provider.addScope('name');

      final credential = await FirebaseAuth.instance.signInWithProvider(
        provider,
      );
      final user = credential.user;
      final resolvedName = Global.firebaseCredentialDisplayName(credential);
      if (mounted) {
        final signed = await Global.loginWithApple(
          context,
          email: user?.email ?? '',
          name: resolvedName,
          appleId: user?.uid ?? '',
        );
        if (signed && mounted) {
          context.pop(true);
        } else if (mounted) {
          setState(() {});
        }
      }
    } on Exception catch (e) {
      Global.logger.d(e);
    } finally {
      cancel();
    }
  }

  _emailLogin() async {
    final result = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => _EmailLogin()));
    if (result == true) {
      if (mounted) {
        context.pop(true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Image.asset(
              'assets/images/android/bg_login.png',
              fit: BoxFit.fitWidth,
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _LoginToolbar(onBack: context.pop),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(horizontal: 15),
                    child: Column(
                      children: [
                        SizedBox(height: 120),
                        Image.asset(
                          'assets/images/android/ic_logo_login.png',
                          width: 130,
                          fit: BoxFit.fitWidth,
                        ),
                        SizedBox(height: 100),
                        if (kIsWeb ||
                            Global.webPreview ||
                            (!kIsWeb &&
                                defaultTargetPlatform ==
                                    TargetPlatform.iOS)) ...[
                          _LoginButton(
                            icon: 'assets/images/apple.svg',
                            text: t.login_apple,
                            onTap: _onAppleSign,
                          ),
                          SizedBox(height: 16),
                        ],
                        _LoginButton(
                          icon: 'assets/images/android/ic_google_login.svg',
                          text: t.log_in_with_google,
                          onTap: _onGoogleSign,
                        ),
                        SizedBox(height: 16),
                        _LoginButton(
                          icon: 'assets/images/android/ic_email_login.svg',
                          text: t.log_in_with_e_mail,
                          onTap: _emailLogin,
                        ),
                        SizedBox(height: 50),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(15, 0, 15, 16),
                  child: _AgreementText(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginToolbar extends StatelessWidget {
  const _LoginToolbar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: EdgeInsetsDirectional.only(start: 15),
          child: InkWell(
            onTap: onBack,
            child: SizedBox(
              width: 24,
              height: 24,
              child: SvgPicture.asset(
                'assets/images/android/ic_toolbar_back.svg',
                width: 24,
                height: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginButton extends StatelessWidget {
  const _LoginButton({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  final String icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 48,
        padding: EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: Color(0xff212121),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SvgPicture.asset(icon, width: 24, height: 24),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            SizedBox(width: 36),
          ],
        ),
      ),
    );
  }
}

class _AgreementText extends StatefulWidget {
  @override
  State<_AgreementText> createState() => _AgreementTextState();
}

class _AgreementTextState extends State<_AgreementText> {
  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () => _openPolicy('service');
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => _openPolicy('privacy');
  }

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  Future<void> _openPolicy(String key) async {
    final title = key == 'service' ? t.user_agreement : t.privacy_policy;
    final fallbackTitle = key == 'service'
        ? 'terms_of_service'
        : 'privacy_policy';
    var url = 'https://yogoshort.com/page/text?title=$fallbackTitle';
    final result = await api<Map<String, dynamic>>(
      'home/policy',
      method: Method.post,
      loading: false,
    );
    final remoteUrl = result.d?[key]?.toString() ?? '';
    if (remoteUrl.isNotEmpty) {
      url = remoteUrl;
    }
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PolicyWebView(title: title, url: url),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parts = t.login_agree.split('||');
    final normalStyle = TextStyle(
      color: Color(0xff999999),
      fontSize: 12,
      height: 1.35,
    );
    final linkStyle = normalStyle.copyWith(
      color: Colors.white,
      decoration: TextDecoration.underline,
      decorationColor: Colors.white,
    );
    return Text.rich(
      TextSpan(
        style: normalStyle,
        children: [
          TextSpan(text: parts.elementAtOrNull(0) ?? ''),
          if (parts.length > 1)
            TextSpan(
              text: parts[1],
              style: linkStyle,
              recognizer: _termsRecognizer,
            ),
          if (parts.length > 2) TextSpan(text: parts[2]),
          if (parts.length > 3)
            TextSpan(
              text: parts[3],
              style: linkStyle,
              recognizer: _privacyRecognizer,
            ),
          if (parts.length > 4) TextSpan(text: parts.sublist(4).join('')),
        ],
      ),
      textAlign: TextAlign.center,
      strutStyle: StrutStyle(
        fontSize: 12,
        height: 1.35,
        forceStrutHeight: true,
      ),
    );
  }
}

class _EmailLogin extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return _EmailLoginState();
  }
}

class _EmailLoginState extends State<_EmailLogin> {
  final _emailController = TextEditingController();
  final _codeNode = FocusNode();
  Timer? _timer;
  int _time = 0;
  String _email = '';
  String _code = '';

  @override
  initState() {
    super.initState();
    final time = Global.sp.getInt('mail-code-expire');
    final now = DateTime.now().millisecondsSinceEpoch;
    if (time != null) {
      if (now < time) {
        _time = ((time - now) / 1000).ceil();
        _startTimer();
      }
    }

    _email = Global.sp.getString('email') ?? '';
    _emailController.text = _email;
  }

  _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: 1), (_) {
      if (_time <= 0) {
        _timer?.cancel();
      }
      setState(() {
        if (_time > 0) {
          _time -= 1;
        }
      });
    });
  }

  _sendCode() async {
    if (_time > 0) {
      return;
    }
    if (!_email.isValidEmail) {
      Global.warning(t.invalid_email);
      return;
    }
    _codeNode.requestFocus();

    final close = Global.loading();

    final result = await api(
      'login/email/code',
      method: Method.post,
      data: {'email': _email},
    );

    close();

    if (result.c != 0) {
      return;
    }

    Global.success(t.email_code_sended);

    Global.sp.setInt(
      'mail-code-expire',
      DateTime.now().millisecondsSinceEpoch + 60000,
    );
    setState(() {
      _time = 59;
    });
    _startTimer();
  }

  _submit() async {
    if (!_email.isValidEmail) {
      Global.error(t.invalid_email);
      return;
    }

    if (_code.isEmpty) {
      Global.error(t.invalid_email_code);
      return;
    }

    Global.sp.setString('email', _email);

    final close = Global.loading();

    try {
      final result = await api(
        'login/email',
        method: Method.post,
        data: {'email': _email, 'code': _code, ...AdjustTracking.loginParams()},
      );

      if (result.c != 0) {
        return;
      }

      final data = result.d is Map ? result.d as Map : const {};
      final info = data['info'];
      final isNew =
          data['is_new'] == true ||
          data['is_new'] == 1 ||
          data['is_new']?.toString() == '1';

      final value = await Global.cacheUserInfo(
        info,
        token: data['token']?.toString(),
        clearAvatar: true,
      );
      if (value == null) {
        Global.error(t.login_failed);
        return;
      }

      if (!kIsWeb && !Global.webPreview) {
        unawaited(_syncFirebaseEmail(info, isNew: isNew));
      }
      if (mounted) {
        context.read<UserState>().set(value);
      }
      if (isNew) {
        AdjustTracking.trackRegister();
      }
      AdjustTracking.trackLogin();
      Global.success(t.login_success);
      if (mounted) {
        context.pop(true);
      }
    } on Exception catch (e) {
      Global.logger.d(e);
      Global.error(t.login_failed);
    } finally {
      close();
    }
  }

  Future<void> _syncFirebaseEmail(dynamic info, {required bool isNew}) async {
    final map = info is Map ? info : const {};
    final password = map['password']?.toString() ?? '';
    if (password.isEmpty) {
      Global.logger.d('email firebase sync skipped: missing password');
      return;
    }
    final credential = EmailAuthProvider.credential(
      email: _email,
      password: password,
    );
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (isNew && currentUser?.isAnonymous == true) {
        try {
          await currentUser?.linkWithCredential(credential);
          return;
        } on FirebaseAuthException catch (error) {
          if (error.code != 'email-already-in-use' &&
              error.code != 'credential-already-in-use') {
            rethrow;
          }
        }
      }
      await FirebaseAuth.instance.signInWithCredential(credential);
    } on FirebaseAuthException catch (error) {
      Global.logger.d(
        'email firebase sync failed code=${error.code} message=${error.message}',
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _codeNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSendCode = _email.isNotEmpty && _time <= 0;
    final canLogin = _email.isNotEmpty && _code.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AndroidToolbar(
              title: t.log_in_with_e_mail,
              onBack: () => Navigator.pop(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(15, 30, 15, 24),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _EmailFieldTitle(
                      icon: 'assets/images/android/ic_email_login.svg',
                      text: t.email_address,
                    ),
                    SizedBox(height: 9),
                    SizedBox(
                      height: 44,
                      child: TextField(
                        autofocus: true,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        controller: _emailController,
                        style: _emailInputTextStyle,
                        cursorColor: Color(0xffff385c),
                        onTapOutside: (_) {
                          FocusManager.instance.primaryFocus?.unfocus();
                        },
                        onChanged: (value) {
                          setState(() {
                            _email = value.trim();
                          });
                        },
                        decoration: _emailInputDecoration(
                          hintText: t.enter_your_email,
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                    _EmailFieldTitle(
                      icon: 'assets/images/android/ic_verify_code.svg',
                      text: t.email_address,
                    ),
                    SizedBox(height: 9),
                    Container(
                      height: 44,
                      padding: EdgeInsetsDirectional.only(start: 12, end: 6),
                      decoration: BoxDecoration(
                        color: Color(0xff333333),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              focusNode: _codeNode,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.go,
                              style: _emailInputTextStyle,
                              cursorColor: Color(0xffff385c),
                              onTapOutside: (_) {
                                FocusManager.instance.primaryFocus?.unfocus();
                              },
                              onChanged: (value) {
                                setState(() {
                                  _code = value.trim();
                                });
                              },
                              onSubmitted: (_) => _submit(),
                              decoration: _emailInputDecoration(
                                hintText: t.enter_code,
                                contentPadding: EdgeInsets.zero,
                                filled: false,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          _AndroidSmallButton(
                            text: _time > 0
                                ? _time.toString().padLeft(2, '0')
                                : t.get_code,
                            enabled: canSendCode,
                            onTap: _sendCode,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 24),
                    _AndroidFullButton(
                      text: t.login,
                      enabled: canLogin,
                      onTap: _submit,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(15, 0, 15, 16),
              child: _AgreementText(),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmailFieldTitle extends StatelessWidget {
  const _EmailFieldTitle({required this.icon, required this.text});

  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SvgPicture.asset(icon, width: 20, height: 20),
        SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _AndroidSmallButton extends StatelessWidget {
  const _AndroidSmallButton({
    required this.text,
    required this.enabled,
    required this.onTap,
  });

  final String text;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 80,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? Color(0xffff3d5d) : Color(0xff999999),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

class _AndroidFullButton extends StatelessWidget {
  const _AndroidFullButton({
    required this.text,
    required this.enabled,
    required this.onTap,
  });

  final String text;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? Color(0xffff3d5d) : Color(0xff999999),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

const _emailInputTextStyle = TextStyle(
  color: Colors.white,
  fontSize: 14,
  fontWeight: FontWeight.w400,
  height: 1.2,
);

const _emailHintTextStyle = TextStyle(
  color: Color(0xff888888),
  fontSize: 14,
  fontWeight: FontWeight.w400,
  height: 1.2,
);

InputDecoration _emailInputDecoration({
  required String hintText,
  EdgeInsetsGeometry contentPadding = const EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 13,
  ),
  bool filled = true,
}) {
  return InputDecoration(
    filled: filled,
    fillColor: Color(0xff333333),
    hintText: hintText,
    hintStyle: _emailHintTextStyle,
    contentPadding: contentPadding,
    constraints: BoxConstraints.tightFor(height: 44),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
  );
}
