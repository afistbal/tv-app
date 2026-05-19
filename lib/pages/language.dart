import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/states/restart.dart';

class Language extends StatefulWidget {
  const Language({super.key});

  @override
  State<StatefulWidget> createState() {
    return _Language();
  }
}

const Map<String, String> languages = {
  'en': 'English', // 英语
  'zh-Hant': '繁体中文', // 中文繁体
  'hi': 'हिंदी', // 印地语
  'es': 'Español', // 西班牙语
  'ar': 'العربية', // 阿拉伯语
  'bn': 'বাংলা', // 孟加拉语
  'pt': 'Português', // 葡萄牙语
  'ru': 'Русский', // 俄语
  'ja': '日本語', // 日语
  'ko': '한국어', // 韩语
  'de': 'Deutsch', // 德语
  'fr': 'Français', // 法语
  'id': 'Bahasa Indonesia', // 印尼语
  'ms': 'Bahasa Melayu', // 马来语
  'ur': 'اردو', // 乌尔都语
  'vi': 'Tiếng Việt', // 越南语
  'th': 'ภาษาไทย', // 泰语
  'my': 'ဗမာဘာသာ', // 缅甸语
  'lo': 'ພາສາລາວ', // 老挝语
  'km': 'ភាសាខ្មែរ', // 高棉语
};

class _Language extends State<Language> {
  String _prevLanguage = '';
  String _language = 'en';

  @override
  void initState() {
    super.initState();
    _language =
        LocaleSettings.currentLocale.languageCode +
        (LocaleSettings.currentLocale.scriptCode != null
            ? '-${LocaleSettings.currentLocale.scriptCode}'
            : '');
    _prevLanguage = _language;
  }

  _onSave() async {
    final languageCode = languages.keys.firstWhere(
      (e) => e.startsWith(_language),
    );
    await LocaleSettings.setLocale(
      AppLocale.values.firstWhere(
        (locale) => languageCode.startsWith(locale.languageCode),
      ),
    );
    await Global.sp.setString('locale', languageCode);
    if (mounted) {
      context.read<RestartState>().restart();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t.language),
        actions: [
          TextButton(
            onPressed: _prevLanguage == _language ? null : _onSave,
            child: Text(t.save, style: TextStyle(fontSize: 16)),
          ),
          SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Ink(
          decoration: BoxDecoration(
            color: Color(0x05ffffff),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView.separated(
            separatorBuilder: (context, _) {
              return Divider(height: 1);
            },
            itemCount: languages.length,
            itemBuilder: (context, index) {
              final languageCode = languages.keys.elementAt(index);
              return ListTile(
                onTap: () {
                  setState(() {
                    _language = languageCode;
                  });
                },
                contentPadding: EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 16,
                ),
                title: Text(
                  languages.values.elementAt(index),
                  style: TextStyle(
                    color: _language == languageCode
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
                trailing: _language == languageCode
                    ? Icon(
                        LucideIcons.circleCheck,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : Icon(LucideIcons.circle),
              );
            },
          ),
        ),
      ),
    );
  }
}
