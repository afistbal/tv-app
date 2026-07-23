import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/components/android_toolbar.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/states/user.dart';

class DeleteAccount extends StatefulWidget {
  const DeleteAccount({super.key});

  @override
  State<DeleteAccount> createState() => _DeleteAccountState();
}

class _DeleteAccountState extends State<DeleteAccount> {
  bool _accepted = false;
  bool _deleting = false;
  bool _deleted = false;

  Future<void> _confirmDeletion() async {
    if (!_accepted || _deleting) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xff242424),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          t.delete_account_confirm_title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          t.delete_account_confirm_message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xffb3b3b3),
            fontSize: 16,
            height: 1.5,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xffff3d5d),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t.confirm),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff3b3b3b),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t.cancel),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _deleting = true);
    final result = await api<dynamic>(
      'user/delete',
      method: Method.post,
      loading: false,
    );
    Global.logger.d(
      '[DELETE] user/delete result c=${result.c} message=${result.m}',
    );

    if (!mounted) {
      return;
    }

    if (result.c != 0) {
      setState(() => _deleting = false);
      if (result.m.isEmpty) {
        Global.error(t.account_deletion_failed);
      }
      return;
    }

    await Global.clearDeletedAccountSession();
    if (!mounted) {
      return;
    }
    final anonymousLogin = await Global.logout(context);
    if (!anonymousLogin && mounted) {
      context.read<UserState>().signout();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _deleting = false;
      _deleted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_deleted) {
      return _SuccessView(onDone: () => context.go('/'));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AndroidToolbar(title: t.delete_account, onBack: context.pop),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(15, 18, 15, 24),
                children: [
                  Text(
                    t.account_deletion_instructions,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      height: 1.2,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _InstructionText(text: t.account_deletion_intro),
                  const SizedBox(height: 28),
                  _InstructionText(text: t.account_deletion_irreversible),
                  const SizedBox(height: 28),
                  _InstructionText(text: t.account_deletion_data_erasure),
                  const SizedBox(height: 28),
                  _InstructionText(text: t.account_deletion_vip_subscription),
                  const SizedBox(height: 44),
                  InkWell(
                    onTap: _deleting
                        ? null
                        : () => setState(() => _accepted = !_accepted),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            _accepted
                                ? LucideIcons.circleCheck
                                : LucideIcons.circle,
                            color: _accepted
                                ? const Color(0xffff3d5d)
                                : const Color(0xff999999),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            t.account_deletion_accept_risks,
                            style: const TextStyle(
                              color: Color(0xff999999),
                              fontSize: 16,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _accepted
                            ? const Color(0xffff3d5d)
                            : const Color(0xff242424),
                        foregroundColor: _accepted
                            ? Colors.white
                            : const Color(0xff777777),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _accepted && !_deleting
                          ? _confirmDeletion
                          : null,
                      child: _deleting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              t.delete_account,
                              style: const TextStyle(fontSize: 16),
                            ),
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

class _InstructionText extends StatelessWidget {
  const _InstructionText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xff999999),
        fontSize: 17,
        height: 1.55,
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: Center(
                child: Text(
                  t.delete_account,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(30, 24, 30, 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/android/img_da@2x.png',
                      width: 148,
                      height: 148,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 52),
                    Text(
                      t.account_deletion_success_message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 52),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xffff3d5d),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: onDone,
                        child: Text(t.understood),
                      ),
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
