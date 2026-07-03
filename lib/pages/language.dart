import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/states/restart.dart';

const Map<String, String> languages = {
  'en': 'English',
  'zh-Hant': '繁體中文',
  'ja': '日本語',
  'pt': 'Português',
  'vi': 'Tiếng Việt',
  'th': 'ภาษาไทย',
  'ko': '한국어',
  'id': 'Bahasa Indonesia',
  'de': 'Deutsch',
  'ms': 'Bahasa Malaysia',
  'tr': 'Türkçe',
  'ar': 'العربية',
};

class Language extends StatefulWidget {
  const Language({super.key});

  @override
  State<Language> createState() => _LanguageState();
}

class _LanguageState extends State<Language> {
  late String _language;

  @override
  void initState() {
    super.initState();
    _language = _localeKey(LocaleSettings.currentLocale);
  }

  Future<void> _changeLanguage(String languageCode) async {
    final locale = _appLocaleFromKey(languageCode);
    setState(() {
      _language = languageCode;
    });
    await LocaleSettings.setLocale(locale);
    await Global.sp.setString('locale', languageCode);
    if (mounted) {
      context.read<RestartState>().restart();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t.language)),
      body: ListView.separated(
        padding: EdgeInsets.symmetric(vertical: 8),
        separatorBuilder: (context, _) => Divider(height: 1),
        itemCount: languages.length,
        itemBuilder: (context, index) {
          final languageCode = languages.keys.elementAt(index);
          final active = _language == languageCode;
          return ListTile(
            onTap: () => _changeLanguage(languageCode),
            contentPadding: EdgeInsets.symmetric(horizontal: 16),
            title: Text(
              languages.values.elementAt(index),
              style: TextStyle(
                color: active ? Color(0xffff3d5d) : Colors.white,
              ),
            ),
            trailing: Icon(
              active ? LucideIcons.circleCheck : LucideIcons.circle,
              color: active ? Color(0xffff3d5d) : Colors.white38,
            ),
          );
        },
      ),
    );
  }
}

String _localeKey(AppLocale locale) {
  if (locale == AppLocale.zhHant) {
    return 'zh-Hant';
  }
  return locale.languageCode == 'id' ? 'id' : locale.languageCode;
}

AppLocale _appLocaleFromKey(String key) {
  if (key == 'zh-Hant') {
    return AppLocale.zhHant;
  }
  return AppLocale.values.firstWhere(
    (locale) => locale.languageCode == key,
    orElse: () => AppLocale.en,
  );
}
