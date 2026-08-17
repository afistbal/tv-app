import 'package:flutter_test/flutter_test.dart';
import 'package:yogotv/pages/play.dart';

void main() {
  test('Play accepts movie ids returned as JSON strings', () {
    final page = Play(id: '2835506157225355');

    expect(page.id, 2835506157225355);
  });

  test('Play preserves numeric movie ids', () {
    final page = Play(id: 2835506157225355);

    expect(page.id, 2835506157225355);
  });

  test('Play rejects invalid movie ids without throwing', () {
    final page = Play(id: 'not-a-movie-id');

    expect(page.id, isNull);
  });
}
