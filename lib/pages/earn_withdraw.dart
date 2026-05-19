import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/components/loading.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';

class EarnWithdraw extends StatefulWidget {
  const EarnWithdraw({super.key});

  @override
  State<StatefulWidget> createState() {
    return _EarnWithdraw();
  }
}

class _EarnWithdraw extends State<EarnWithdraw> {
  int _selected = 0;
  int _total = 0;
  double _amount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  _loadData() async {
    final result = await api('earn/withdraw');
    if (result.c != 0) {
      return;
    }
    setState(() {
      _total = result.d['total'];
      _amount = (result.d['amount']).toDouble();
      _loading = false;
    });
  }

  _onSubmit() async {
    var selectedAmount = 10;
    switch (_selected) {
      case 0:
        selectedAmount = 10;
        break;
      case 1:
        selectedAmount = 20;
        break;
      case 2:
        selectedAmount = 50;
        break;
      case 3:
        selectedAmount = 100;
        break;
    }

    if (selectedAmount > _amount) {
      Global.warning(t.not_enough_coins);
      return;
    }

    final result = await api(
      'earn/withdraw',
      method: Method.post,
      loading: true,
      data: {'type': _selected},
    );

    if (result.c != 0) {
      return;
    }
    _loadData();
    Global.success(t.success);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t.withdraw)),
      body: _loading
          ? Loading()
          : Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                spacing: 16,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        t.earn.owned_earn,
                        style: TextStyle(fontSize: 16, color: Colors.white70),
                      ),
                      Text(
                        _total.toString(),
                        style: TextStyle(
                          fontSize: 24,
                          color: Colors.red.shade400,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        t.converted_amount,
                        style: TextStyle(fontSize: 16, color: Colors.white70),
                      ),
                      Text(
                        '\$${_amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 24,
                          color: Colors.green.shade400,
                        ),
                      ),
                    ],
                  ),
                  Divider(height: 1),
                  Text(
                    t.select_withdrawal_amount,
                    style: TextStyle(fontSize: 15, color: Colors.white54),
                  ),
                  Row(
                    spacing: 16,
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _selected = 0;
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Ink(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _selected == 0
                                    ? Colors.white24
                                    : Colors.white10,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              color: _selected == 0
                                  ? Colors.orange.withAlpha(50)
                                  : null,
                            ),
                            child: Text(
                              '\$10.00',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _selected = 1;
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Ink(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _selected == 1
                                    ? Colors.white24
                                    : Colors.white10,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              color: _selected == 1
                                  ? Colors.orange.withAlpha(50)
                                  : null,
                            ),
                            child: Text(
                              '\$20.00',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    spacing: 16,
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _selected = 2;
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Ink(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _selected == 2
                                    ? Colors.white24
                                    : Colors.white10,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              color: _selected == 2
                                  ? Colors.orange.withAlpha(50)
                                  : null,
                            ),
                            child: Text(
                              '\$50.00',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _selected = 3;
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Ink(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _selected == 3
                                    ? Colors.white24
                                    : Colors.white10,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              color: _selected == 3
                                  ? Colors.orange.withAlpha(50)
                                  : null,
                            ),
                            child: Text(
                              '\$100.00',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Divider(height: 1),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _onSubmit,
                    child: Ink(
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: 10,
                      ),
                      child: Row(
                        spacing: 4,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(TablerIcons.credit_card, size: 24),
                          Text(
                            t.withdraw_now,
                            textAlign: TextAlign.center,
                            style: TextStyle(height: 1, fontSize: 16),
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
