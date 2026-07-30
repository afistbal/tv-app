import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PaymentDiagnostics {
  static const bool _releaseEnabled = bool.fromEnvironment(
    'PAYMENT_DIAGNOSTICS',
  );
  static const String _storageKey = 'payment_diagnostics_log_v1';
  static const int _maxEntries = 300;

  static final List<String> _entries = [];
  static SharedPreferences? _preferences;
  static String _appVersion = '';
  static String _buildNumber = '';
  static String _flavor = '';
  static String _apiHost = '';
  static String _stage = 'idle';
  static String _lastFailure = '';
  static bool _lastFailureCanceled = false;
  static int _attempt = 0;

  static bool get enabled => kDebugMode || _releaseEnabled;
  static String get currentStage => _stage;
  static String get lastFailure => _lastFailure;
  static bool get lastFailureCanceled => _lastFailureCanceled;
  static bool get hasFailure => _lastFailure.isNotEmpty;

  static Future<void> initialize({
    required SharedPreferences preferences,
    required String appVersion,
    required String buildNumber,
    required String flavor,
    required String apiHost,
  }) async {
    if (!enabled) {
      return;
    }
    _preferences = preferences;
    _appVersion = appVersion;
    _buildNumber = buildNumber;
    _flavor = flavor;
    _apiHost = apiHost;
    _entries
      ..clear()
      ..addAll(preferences.getStringList(_storageKey) ?? const []);
    add(
      'diagnostics initialized '
      'app=$_appVersion($_buildNumber) flavor=$_flavor '
      'platform=${kIsWeb ? 'web' : Platform.operatingSystem} '
      'os=${kIsWeb ? 'web' : Platform.operatingSystemVersion} '
      'api=$_apiHost',
    );
  }

  static void beginAttempt({
    required String localProductId,
    required String appleProductId,
    required int type,
  }) {
    if (!enabled) {
      return;
    }
    _attempt += 1;
    _stage = 'start';
    _lastFailure = '';
    _lastFailureCanceled = false;
    add(
      '----- attempt=$_attempt begin '
      'localProductId=$localProductId '
      'appleProductId=$appleProductId '
      'kind=${type == 2 ? 'consumable' : 'subscription_or_nonconsumable'} -----',
    );
  }

  static void stage(String value, {String details = ''}) {
    if (!enabled) {
      return;
    }
    _stage = value;
    add('stage=$value${details.isEmpty ? '' : ' $details'}');
  }

  static void add(String message) {
    if (!enabled) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    _entries.add('$now ${_sanitize(message)}');
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    unawaited(_persist());
  }

  static void warning(String stage, String message) {
    if (!enabled) {
      return;
    }
    _stage = stage;
    add('warning stage=$stage message=$message');
  }

  static void failure(
    String stage,
    String message, {
    String code = '',
    bool canceled = false,
  }) {
    if (!enabled) {
      return;
    }
    _stage = stage;
    _lastFailureCanceled = canceled;
    _lastFailure = [
      'stage=$stage',
      if (code.isNotEmpty) 'code=$code',
      'message=$message',
    ].join(' ');
    add('failure $_lastFailure canceled=$canceled');
  }

  static String exportText({String summary = ''}) {
    final header = <String>[
      'Payment diagnostics',
      'App: $_appVersion ($_buildNumber)',
      'Flavor: $_flavor',
      'API: $_apiHost',
      'Current stage: $_stage',
      if (summary.isNotEmpty) 'Summary: $summary',
      if (_lastFailure.isNotEmpty) 'Last failure: $_lastFailure',
      '',
    ];
    return [...header, ..._entries].join('\n');
  }

  static Future<void> clear() async {
    _entries.clear();
    _lastFailure = '';
    _lastFailureCanceled = false;
    _stage = 'idle';
    await _preferences?.remove(_storageKey);
    add('diagnostics log cleared');
  }

  static Future<void> _persist() async {
    await _preferences?.setStringList(_storageKey, List.of(_entries));
  }

  static String _sanitize(String message) {
    var value = message.replaceAll(
      RegExp(r'Bearer\s+[^\s,}]+'),
      'Bearer <redacted>',
    );
    value = value.replaceAll(
      RegExp(r'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}'),
      '<redacted-jws>',
    );
    return value;
  }
}

Future<void> showPaymentDiagnosticsDialog(
  BuildContext context, {
  required String title,
  String summary = '',
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return _PaymentDiagnosticsDialog(title: title, summary: summary);
    },
  );
}

class _PaymentDiagnosticsDialog extends StatefulWidget {
  const _PaymentDiagnosticsDialog({required this.title, required this.summary});

  final String title;
  final String summary;

  @override
  State<_PaymentDiagnosticsDialog> createState() =>
      _PaymentDiagnosticsDialogState();
}

class _PaymentDiagnosticsDialogState extends State<_PaymentDiagnosticsDialog> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final logs = PaymentDiagnostics.exportText(summary: widget.summary);
    return AlertDialog(
      backgroundColor: const Color(0xff1f1f1f),
      title: Text(
        widget.title,
        style: const TextStyle(color: Colors.white, fontSize: 18),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stage: ${PaymentDiagnostics.currentStage}',
              style: const TextStyle(color: Color(0xffffd36a), fontSize: 13),
            ),
            if (widget.summary.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                widget.summary,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xff444444)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(10),
                  child: SelectableText(
                    logs,
                    style: const TextStyle(
                      color: Color(0xffdddddd),
                      fontSize: 11,
                      height: 1.35,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await PaymentDiagnostics.clear();
            if (mounted) {
              setState(() => _copied = false);
            }
          },
          child: const Text('Clear'),
        ),
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: logs));
            if (mounted) {
              setState(() => _copied = true);
            }
          },
          icon: Icon(
            _copied ? LucideIcons.clipboardCheck : LucideIcons.clipboardCopy,
            size: 18,
          ),
          label: Text(_copied ? 'Copied' : 'Copy logs'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
