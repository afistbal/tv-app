import 'package:flutter_test/flutter_test.dart';
import 'package:yogotv/from_source.dart';

void main() {
  const first = 'id=10665&episode=1&p0=22o1da5v&s=A100FB1&fbclid=first-click';
  const next = 'id=10666&episode=2&p0=22o1da5v&s=A100FB2&fbclid=next-click';

  test('keeps a valid landing query as the original string', () {
    final value = FromSourceValue.tryParse(first);

    expect(value, isNotNull);
    expect(value!.raw, same(first));
    expect(value.source, 'A100FB1');
  });

  test('keeps the raw string after Adjust deep link encoding', () {
    final deepLink = Uri(
      scheme: 'com.yogotv.app',
      host: 'open',
      queryParameters: {
        'movieId': '10665',
        'episodeNum': '1',
        'from_source': first,
      },
    );
    final decoded = Uri.parse(
      deepLink.toString(),
    ).queryParameters['from_source'];
    final value = FromSourceValue.tryParse(decoded);

    expect(decoded, equals(first));
    expect(value?.raw, equals(first));
  });

  test('rejects arbitrary input', () {
    expect(FromSourceValue.tryParse('hello'), isNull);
    expect(FromSourceValue.tryParse('https://example.com'), isNull);
    expect(FromSourceValue.tryParse('id=10665&fbclid=test'), isNull);
  });

  test('accepts the first valid landing query', () {
    final selected = FromSourceValue.selectForLogin(
      incoming: first,
      cached: null,
      cachedSourceAnchor: null,
    );

    expect(selected?.raw, same(first));
  });

  test('a changed A100 Facebook source replaces the cached query', () {
    final selected = FromSourceValue.selectForLogin(
      incoming: next,
      cached: first,
      cachedSourceAnchor: 'A100FB1',
    );

    expect(selected?.raw, same(next));
  });

  test('the same source does not replace the cached query', () {
    const sameSource =
        'id=10666&episode=2&p0=22o1da5v&s=A100FB1&fbclid=next-click';

    final selected = FromSourceValue.selectForLogin(
      incoming: sameSource,
      cached: first,
      cachedSourceAnchor: 'A100FB1',
    );

    expect(selected?.raw, same(first));
  });

  test('a non-campaign source cannot replace the cached query', () {
    const nonCampaign =
        'id=10666&episode=2&p0=22o1da5v&s=ORGANIC&fbclid=next-click';

    final selected = FromSourceValue.selectForLogin(
      incoming: nonCampaign,
      cached: first,
      cachedSourceAnchor: 'A100FB1',
    );

    expect(selected?.raw, same(first));
  });

  test('an A100 source without FB or TikTok context cannot replace', () {
    const noMedia = 'id=10666&episode=2&p0=22o1da5v&s=A100OTHER';

    final selected = FromSourceValue.selectForLogin(
      incoming: noMedia,
      cached: first,
      cachedSourceAnchor: 'A100FB1',
    );

    expect(selected?.raw, same(first));
  });
}
