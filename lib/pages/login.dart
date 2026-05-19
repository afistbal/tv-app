import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/components/modal_bottom.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/main.dart';
import 'package:yogotv/states/user.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<StatefulWidget> createState() {
    return _Login();
  }
}

class _Login extends State<Login> {
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
        scopes: ['email', 'profile'],
      ).signIn();

      final GoogleSignInAuthentication? googleAuth =
          await googleUser?.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth?.accessToken,
        idToken: googleAuth?.idToken,
      );

      if (FirebaseAuth.instance.currentUser != null &&
          FirebaseAuth.instance.currentUser!.isAnonymous) {
        try {
          await FirebaseAuth.instance.currentUser?.linkWithCredential(
            credential,
          );
        } on FirebaseAuthException catch (e) {
          switch (e.code) {}
        }
      }

      await FirebaseAuth.instance.signInWithCredential(credential);

      if (mounted) {
        await Global.login(context);
        setState(() {});
      }
    } on Exception catch (e) {
      Global.logger.d(e.toString());
    } finally {
      cancel();
    }
  }

  _onAppleSign() async {
    final cancel = Global.loading();
    try {
      final provider = AppleAuthProvider();
      provider.addScope('email');

      await FirebaseAuth.instance.signInWithProvider(provider);

      if (mounted) {
        await Global.login(context);
        setState(() {});
      }
    } on Exception catch (e) {
      Global.logger.d(e);
    } finally {
      cancel();
    }
  }

  _emailLogin() async {
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _EmailLogin();
      },
    );
    if (result == true) {
      setState(() {});
    }
  }

  _deleteAccount() async {
    final cancel = Global.loading();
    try {
      await api('user/delete', method: Method.post, loading: false);
      await FirebaseAuth.instance.currentUser?.delete();
      await Global.sp.remove('token');
      if (mounted) {
        Global.login(context);
      }
    } on Exception catch (e) {
      Global.logger.d(e);
    } finally {
      cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final userState = context.read<UserState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(userState.signed ? t.account_infomation : t.login),
      ),
      body: userState.signed
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: Color(0x10ffffff),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Wrap(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 16,
                          ),
                          title: Text(
                            t.id,
                            style: TextStyle(color: Colors.white60),
                          ),
                          trailing: Text(
                            userState.state?.uniqueId ?? '',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                        Divider(height: 1),
                        ListTile(
                          contentPadding: EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 16,
                          ),
                          title: Text(
                            t.user_name,
                            style: TextStyle(color: Colors.white60),
                          ),
                          trailing: Text(
                            userState.state?.name ?? '',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                        Divider(height: 1),
                        ListTile(
                          contentPadding: EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 16,
                          ),
                          title: Text(
                            t.user_type,
                            style: TextStyle(color: Colors.white60),
                          ),
                          trailing: Text(
                            userState.state!.vip == 0 ? t.vip_0 : t.vip_1,
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                        Divider(height: 1),
                        ListTile(
                          onTap: () async {
                            final result = await context.push(
                              '/alert',
                              extra: {
                                'title': t.delete_account,
                                'content': t.alert_delete_account,
                              },
                            );
                            if (result == true) {
                              _deleteAccount();
                            }
                          },
                          contentPadding: EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 16,
                          ),
                          title: Text(
                            t.delete_account,
                            style: TextStyle(color: Colors.white60),
                          ),
                          trailing: Icon(Icons.arrow_forward_ios, size: 18),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton(
                    onPressed: () async {
                      final cancel = Global.loading();
                      await Global.logout(context);
                      setState(() {});
                      cancel();
                    },
                    child: Row(
                      spacing: 4,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.logOut, size: 20),
                        Text(t.logout, style: TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : Column(
              spacing: 16,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  height: 192,
                  child: Center(
                    child: Text(t.site_name, style: TextStyle(fontSize: 32)),
                  ),
                ),
                if (Platform.isIOS)
                  Button(
                    onTap: _onAppleSign,
                    width: 280,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      spacing: 8,
                      children: [
                        SvgPicture.asset(
                          'assets/images/apple.svg',
                          width: 24,
                          height: 24,
                        ),
                        Expanded(
                          child: Text(
                            t.login_apple,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                Button(
                  onTap: _onGoogleSign,
                  width: 280,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: 8,
                    children: [
                      SvgPicture.asset(
                        'assets/images/google.svg',
                        width: 24,
                        height: 24,
                      ),
                      Expanded(
                        child: Text(
                          t.login_google,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
                Button(
                  onTap: _emailLogin,
                  width: 280,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: 8,
                    children: [
                      SvgPicture.asset(
                        'assets/images/email.svg',
                        width: 24,
                        height: 24,
                      ),
                      Expanded(
                        child: Text(
                          t.login_email,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
        data: {'email': _email, 'code': _code},
      );

      if (result.c != 0) {
        return;
      }
      final credential = EmailAuthProvider.credential(
        email: _email,
        password: result.d['info']['password'],
      );
      if (result.d['is_new']) {
        await FirebaseAuth.instance.currentUser?.linkWithCredential(credential);
      } else {
        await FirebaseAuth.instance.signInWithCredential(credential);
      }

      if (mounted) {
        context.read<UserState>().set(
          UserStateValue(
            name: result.d['info']['name'] ?? 'No Name',
            uniqueId: result.d['info']['unique_id'],
            password: result.d['info']['password'],
            vip: result.d['info']['vip'],
            admin: result.d['info']['admin'],
            anonymous: result.d['info']['anonymous'],
          ),
        );
        context.pop(true);
      }

      Global.success(t.login_success);
    } on FirebaseAuthException catch (e) {
      Global.logger.d(e);
    } finally {
      close();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ModalBottom(
      title: t.login_email,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 8),
          Divider(height: 1),
          Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              spacing: 16,
              children: [
                TextField(
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  onTapOutside: (event) {
                    FocusManager.instance.primaryFocus?.unfocus();
                  },
                  onChanged: (value) {
                    _email = value.trim();
                  },
                  decoration: InputDecoration(
                    prefixIcon: SizedBox(
                      width: 64,
                      child: Icon(LucideIcons.mail),
                    ),
                    hintText: t.email_placeholder,
                  ),
                ),
                TextField(
                  focusNode: _codeNode,
                  keyboardType: TextInputType.numberWithOptions(),
                  textInputAction: TextInputAction.go,
                  onTapOutside: (event) {
                    FocusManager.instance.primaryFocus?.unfocus();
                  },
                  onChanged: (value) {
                    _code = value.trim();
                  },
                  onSubmitted: (_) {
                    _submit();
                  },
                  decoration: InputDecoration(
                    prefixIcon: SizedBox(
                      width: 64,
                      child: Icon(LucideIcons.shield),
                    ),
                    contentPadding: EdgeInsets.zero,
                    suffixIcon: InkWell(
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                      onTap: _sendCode,
                      child: Center(
                        child: Text(
                          _time > 0
                              ? _time.toString().padLeft(2, '0')
                              : t.send_code,
                          style: TextStyle(fontSize: 16, color: Colors.red),
                        ),
                      ),
                    ),
                    suffixIconConstraints: BoxConstraints(
                      maxHeight: 56,
                      minHeight: 56,
                      maxWidth: 72,
                      minWidth: 72,
                    ),
                    hintText: t.code_placeholder,
                  ),
                ),
                FilledButton(
                  onPressed: _submit,
                  child: Row(
                    spacing: 4,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(TablerIcons.login, size: 20),
                      Text(t.login, style: TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class Button extends StatelessWidget {
  final Widget child;
  final double? width;
  final void Function()? onTap;

  const Button({super.key, required this.child, this.width, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(16),
        ),
        width: width,
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: child,
      ),
    );
  }
}
