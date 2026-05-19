import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/components/ok.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/main.dart';

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
  bool _submitted = false;

  _onSubmit() async {
    if (_content.length < 5) {
      Global.warning(t.feedback_content_invalid);
      return;
    }
    if (_content.length < 5) {
      Global.warning(t.feedback_content_invalid);
      return;
    }

    if (!_email.isValidEmail) {
      Global.warning(t.invalid_email);
      return;
    }

    final close = Global.loading();

    await api(
      'feedback',
      method: Method.post,
      data: {'email': _email, 'content': _content},
    );

    close();

    setState(() {
      _submitted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t.feedback_help)),
      body: _submitted
          ? Ok(message: t.feedback_submitted)
          : SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  spacing: 16,
                  children: [
                    TextField(
                      onTapOutside: (_) {
                        FocusManager.instance.primaryFocus?.unfocus();
                      },
                      onChanged: (value) {
                        _content = value.trim();
                      },
                      maxLines: 8,
                      decoration: InputDecoration(
                        hintText: t.feedback_placeholder,
                      ),
                    ),
                    TextField(
                      onTapOutside: (_) {
                        FocusManager.instance.primaryFocus?.unfocus();
                      },
                      onChanged: (value) {
                        _email = value.trim();
                      },
                      decoration: InputDecoration(
                        hintText: t.email_placeholder,
                        prefixIcon: Icon(LucideIcons.mail),
                      ),
                    ),
                    FilledButton(
                      onPressed: _onSubmit,
                      child: Row(
                        spacing: 4,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(TablerIcons.send, size: 20),
                          Text(t.submit, style: TextStyle(fontSize: 16)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
