import 'package:flutter_test/flutter_test.dart';
import 'package:yogotv/vip_content_refresh.dart';

void main() {
  tearDown(VipContentRefresh.reset);

  test('VIP status only changes when crossing zero', () {
    expect(VipContentRefresh.statusChanged(0, 1), isTrue);
    expect(VipContentRefresh.statusChanged(1, 0), isTrue);
    expect(VipContentRefresh.statusChanged(0, 0), isFalse);
    expect(VipContentRefresh.statusChanged(1, 2), isFalse);
  });

  test('home and For You refresh independently on their next tab entry', () {
    VipContentRefresh.markVipChanged();

    expect(VipContentRefresh.takeHome(), isTrue);
    expect(VipContentRefresh.takeHome(), isFalse);
    expect(VipContentRefresh.takeForYou(), isTrue);
    expect(VipContentRefresh.takeForYou(), isFalse);
  });
}
