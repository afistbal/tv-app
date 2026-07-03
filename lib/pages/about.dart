import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yogotv/app_config.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';

class About extends StatefulWidget {
  const About({super.key});

  @override
  State<StatefulWidget> createState() {
    return _About();
  }
}

class _About extends State<About> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t.about_us)),
      body: Column(
        spacing: 16,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: 192,
            child: Center(
              child: Column(
                spacing: 8,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/icon.png',
                      width: 64,
                      height: 64,
                    ),
                  ),
                  Text(
                    AppConfig.current.brandDisplayName,
                    style: TextStyle(fontSize: 20),
                  ),
                ],
              ),
            ),
          ),
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
                    onTap: () {
                      launchUrl(Uri.parse('https://ddkk.hk/user-terms.html'));
                    },
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 16,
                    ),
                    title: Text(t.user_agreement),
                    trailing: Icon(Icons.arrow_forward_ios, size: 18),
                  ),
                  Divider(height: 1),
                  ListTile(
                    onTap: () {
                      launchUrl(
                        Uri.parse('https://ddkk.hk/privacy-policy.html'),
                      );
                    },
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 16,
                    ),
                    title: Text(t.privacy_policy),
                    trailing: Icon(Icons.arrow_forward_ios, size: 18),
                  ),
                  Divider(height: 1),
                  ListTile(
                    onTap: () async {
                      InAppReview.instance.isAvailable().then((value) async {
                        if (value) {
                          await InAppReview.instance.requestReview();
                        } else {
                          Global.error(t.failed);
                        }
                      });
                    },
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 16,
                    ),
                    title: Text(t.rating),
                    trailing: Icon(Icons.arrow_forward_ios, size: 18),
                  ),
                  Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 16,
                    ),
                    title: Text(t.version),
                    subtitle: Text(
                      '${Global.packageInfo.installTime}',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    trailing: Text(
                      '${Global.packageInfo.version}(${Global.packageInfo.buildNumber})',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
