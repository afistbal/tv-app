import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yogotv/components/android_toolbar.dart';
import 'package:yogotv/components/android_prompt_dialog.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/states/user.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _version = info.version);
      }
    });
  }

  Future<void> _openUrl(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _rateUs() async {
    final available = await InAppReview.instance.isAvailable();
    if (available) {
      await InAppReview.instance.requestReview();
    } else {
      Global.error(t.failed);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showAndroidPromptDialog(
      context: context,
      title: t.sign_out,
      content: t.signing_out_may_affect_your_user_experience_confirm,
    );
    if (!confirmed || !mounted) {
      return;
    }
    final close = Global.loading();
    final signedOut = await Global.logout(context);
    close();
    if (signedOut && mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final signed = context.watch<UserState>().signed;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AndroidToolbar(title: t.setting, onBack: context.pop),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Column(
                        children: [
                          _SettingsRow(
                            title: t.terms_of_service,
                            showArrow: true,
                            topRadius: true,
                            onTap: () => _openUrl(
                              'https://yogoshort.com/page/text?title=terms_of_service',
                            ),
                          ),
                          _DividerLine(),
                          _SettingsRow(
                            title: t.privacy_policy,
                            showArrow: true,
                            onTap: () => _openUrl(
                              'https://yogoshort.com/page/text?title=privacy_policy',
                            ),
                          ),
                          _DividerLine(),
                          _SettingsRow(
                            title: t.rating,
                            showArrow: true,
                            onTap: _rateUs,
                          ),
                          _DividerLine(),
                          _SettingsRow(
                            title: t.version,
                            trailing: _version,
                            bottomRadius: true,
                            onTap: () =>
                                Global.info(t.this_is_the_latest_version),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                    if (!signed)
                      _ActionButton(
                        text: t.log_in,
                        color: Color(0xffff3d5d),
                        onTap: () => context.push('/login'),
                      )
                    else
                      _ActionButton(
                        text: t.sign_out,
                        color: Color(0xff212121),
                        onTap: _signOut,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    this.trailing = '',
    this.showArrow = false,
    this.topRadius = false,
    this.bottomRadius = false,
    this.onTap,
  });

  final String title;
  final String trailing;
  final bool showArrow;
  final bool topRadius;
  final bool bottomRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 52,
        padding: EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Color(0xff212121),
          borderRadius: BorderRadius.vertical(
            top: topRadius ? Radius.circular(12) : Radius.zero,
            bottom: bottomRadius ? Radius.circular(12) : Radius.zero,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            if (trailing.isNotEmpty)
              Text(
                trailing,
                style: TextStyle(color: Color(0xff999999), fontSize: 14),
              ),
            if (showArrow) ...[
              SizedBox(width: 8),
              Icon(
                LucideIcons.chevronRight,
                color: Color(0xff999999),
                size: 14,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DividerLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: Color(0xff212121),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 12),
        color: Colors.white.withAlpha(26),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.text,
    required this.color,
    required this.onTap,
  });

  final String text;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: TextStyle(color: Colors.white, fontSize: 16)),
      ),
    );
  }
}
