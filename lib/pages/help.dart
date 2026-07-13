import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/components/android_toolbar.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';

class Help extends StatefulWidget {
  const Help({super.key});

  @override
  State<StatefulWidget> createState() {
    return _Help();
  }
}

class _Help extends State<Help> {
  String _content = '';
  String _email = '';

  _onSubmit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_content.isEmpty || _email.isEmpty) {
      return;
    }

    final close = Global.loading();

    await api(
      'feedback',
      method: Method.post,
      data: {'email': _email, 'content': _content},
    );

    close();
    if (!mounted) {
      return;
    }
    Global.success(t.success);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _content.isNotEmpty && _email.isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AndroidToolbar(title: t.feedback_help, onBack: context.pop),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 160,
                      child: TextField(
                        onTapOutside: (_) {
                          FocusManager.instance.primaryFocus?.unfocus();
                        },
                        onChanged: (value) {
                          setState(() => _content = value.trim());
                        },
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.2,
                        ),
                        decoration: _androidInputDecoration(
                          hint: t.feedback_input_hint,
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          t.star_mark,
                          style: const TextStyle(
                            color: Color(0xffff3d5d),
                            fontSize: 14,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          t.email,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 44,
                      child: TextField(
                        onTapOutside: (_) {
                          FocusManager.instance.primaryFocus?.unfocus();
                        },
                        onChanged: (value) {
                          setState(() => _email = value.trim());
                        },
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.2,
                        ),
                        decoration: _androidInputDecoration(
                          hint: t.enter_your_email,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: canSubmit ? _onSubmit : null,
                      child: Container(
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: canSubmit
                              ? const Color(0xffff3d5d)
                              : const Color(0xff999999),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          t.submit,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            height: 1.2,
                          ),
                        ),
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

InputDecoration _androidInputDecoration({
  required String hint,
  required EdgeInsetsGeometry contentPadding,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(
      color: Color(0xff999999),
      fontSize: 14,
      height: 1.2,
    ),
    filled: true,
    fillColor: const Color(0xff212121),
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
    contentPadding: contentPadding,
  );
}
