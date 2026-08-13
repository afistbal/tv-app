import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yogotv/playback_progress_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PlaybackProgressStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = PlaybackProgressStore(await SharedPreferences.getInstance());
  });

  test('stores progress by uid, movie, and episode', () async {
    await store.writeSeconds(
      uid: 'profile-user-1',
      movieId: 'movie-8',
      episodeId: 'episode-3',
      seconds: 37,
    );

    expect(
      store.readSeconds(
        uid: 'profile-user-1',
        movieId: 'movie-8',
        episodeId: 'episode-3',
      ),
      37,
    );
    expect(
      store.readSeconds(
        uid: 'profile-user-2',
        movieId: 'movie-8',
        episodeId: 'episode-3',
      ),
      isNull,
    );
    expect(
      store.readSeconds(
        uid: 'profile-user-1',
        movieId: 'movie-8',
        episodeId: 'episode-4',
      ),
      isNull,
    );
  });

  test('keeps zero seconds for a completed episode', () async {
    await store.writeSeconds(
      uid: 'profile-user-1',
      movieId: 'movie-8',
      episodeId: 'episode-3',
      seconds: 0,
    );

    expect(
      store.readSeconds(
        uid: 'profile-user-1',
        movieId: 'movie-8',
        episodeId: 'episode-3',
      ),
      0,
    );
  });
}
