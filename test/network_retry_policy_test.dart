import 'package:flutter_test/flutter_test.dart';
import 'package:yogotv/network_retry_policy.dart';

void main() {
  test('retries safe query requests', () {
    expect(isSafeNetworkRetry(path: 'user/membership', isGet: false), isTrue);
    expect(
      isSafeNetworkRetry(path: 'feed/membership?page=1', isGet: false),
      isTrue,
    );
    expect(
      isSafeNetworkRetry(
        path: 'movie/episode',
        isGet: false,
        data: {'id': 1, 'auto_unlock': '0'},
      ),
      isTrue,
    );
  });

  test('does not retry state-changing requests', () {
    expect(
      isSafeNetworkRetry(
        path: 'movie/history/report',
        isGet: false,
        data: {'duration': 1},
      ),
      isFalse,
    );
    expect(
      isSafeNetworkRetry(path: 'movie/favorite', isGet: false, data: {'id': 1}),
      isFalse,
    );
    expect(
      isSafeNetworkRetry(
        path: 'movie/episode',
        isGet: false,
        data: {'id': 1, 'auto_unlock': '1'},
      ),
      isFalse,
    );
    expect(
      isSafeNetworkRetry(
        path: 'user/config',
        isGet: false,
        data: {'wallet': true},
      ),
      isFalse,
    );
  });
}
