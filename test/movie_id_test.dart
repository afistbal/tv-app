import 'package:flutter_test/flutter_test.dart';
import 'package:yogotv/movie_id.dart';

void main() {
  test('parses movie ids from every supported API field', () {
    expect(parseMovieId({'id': '2835506157225355'}), 2835506157225355);
    expect(parseMovieId({'movie_id': 2835506157225355}), 2835506157225355);
    expect(parseMovieId({'movieId': '2835506157225355'}), 2835506157225355);
    expect(parseMovieId({'moveId': '2835506157225355'}), 2835506157225355);
  });

  test('prefers the explicit movie id fields over generic id', () {
    expect(
      parseMovieId({'movie_id': '2835506157225355', 'id': 329965}),
      2835506157225355,
    );
  });

  test('rejects missing, invalid, and non-positive movie ids', () {
    expect(parseMovieId(null), isNull);
    expect(parseMovieId('not-a-movie-id'), isNull);
    expect(parseMovieId(0), isNull);
    expect(parseMovieId(-1), isNull);
  });
}
