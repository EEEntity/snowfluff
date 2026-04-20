import 'package:hive_ce_flutter/hive_ce_flutter.dart';

class PlaybackCachedSong {
  final int id;
  final String title;
  final String artist;
  final int durationMs;
  final String artUri;
  final List<int> artistIds;

  const PlaybackCachedSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.durationMs,
    required this.artUri,
    required this.artistIds,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id.toString(),
      'title': title,
      'artist': artist,
      'durationMs': durationMs,
      'artUri': artUri,
      'artistIds': artistIds
          .map((int e) => e.toString())
          .toList(growable: false),
    };
  }

  static PlaybackCachedSong? fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return null;
    final int id = int.tryParse(map['id']?.toString() ?? '') ?? 0;
    if (id <= 0) return null;
    final dynamic rawArtistIds = map['artistIds'];
    final List<int> artistIds = rawArtistIds is List
        ? rawArtistIds
              .map((dynamic e) => int.tryParse(e.toString()) ?? 0)
              .where((int e) => e > 0)
              .toList(growable: false)
        : const <int>[];
    return PlaybackCachedSong(
      id: id,
      title: map['title']?.toString() ?? '歌曲$id',
      artist: map['artist']?.toString() ?? '',
      durationMs: int.tryParse(map['durationMs']?.toString() ?? '') ?? 0,
      artUri: map['artUri']?.toString() ?? '',
      artistIds: artistIds,
    );
  }
}

class PlaybackCacheState {
  final List<PlaybackCachedSong> queueSongs;
  final int currentIndex;
  final int currentSongId;
  final int? backgroundColorArgb;
  final String loopMode;
  final bool wasPlaying;
  final String queueName;
  final bool shuffleEnabled;
  final bool isFMMode;

  const PlaybackCacheState({
    required this.queueSongs,
    required this.currentIndex,
    required this.currentSongId,
    this.backgroundColorArgb,
    required this.loopMode,
    required this.wasPlaying,
    required this.queueName,
    this.shuffleEnabled = false,
    this.isFMMode = false,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'queueSongs': queueSongs
          .map((PlaybackCachedSong song) => song.toMap())
          .toList(growable: false),
      'currentIndex': currentIndex,
      'currentSongId': currentSongId.toString(),
      if (backgroundColorArgb != null)
        'backgroundColorArgb': backgroundColorArgb,
      'loopMode': loopMode,
      'wasPlaying': wasPlaying,
      'queueName': queueName,
      'shuffleEnabled': shuffleEnabled,
      'isFMMode': isFMMode,
    };
  }

  static PlaybackCacheState? fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return null;
    final dynamic rawQueueSongs = map['queueSongs'];
    List<PlaybackCachedSong> queueSongs = rawQueueSongs is List
        ? rawQueueSongs
              .map(
                (dynamic e) => e is Map ? PlaybackCachedSong.fromMap(e) : null,
              )
              .whereType<PlaybackCachedSong>()
              .toList(growable: false)
        : const <PlaybackCachedSong>[];
    if (queueSongs.isEmpty) return null;
    final dynamic rawBgColor = map['backgroundColorArgb'];
    final int? bgColorArgb = rawBgColor == null
        ? null
        : int.tryParse(rawBgColor.toString());
    return PlaybackCacheState(
      queueSongs: queueSongs,
      currentIndex: int.tryParse(map['currentIndex'].toString()) ?? 0,
      currentSongId: int.tryParse(map['currentSongId'].toString()) ?? 0,
      backgroundColorArgb: bgColorArgb,
      loopMode: map['loopMode']?.toString() ?? 'one',
      wasPlaying: map['wasPlaying'] == true,
      queueName: map['queueName']?.toString() ?? '',
      shuffleEnabled: map['shuffleEnabled'] == true,
      isFMMode: map['isFMMode'] == true,
    );
  }
}

class PlaybackStateCacheService {
  PlaybackStateCacheService._internal();

  static final PlaybackStateCacheService _instance =
      PlaybackStateCacheService._internal();

  factory PlaybackStateCacheService() => _instance;

  static const String _boxName = 'playback_state_cache_v1';
  static const String _stateKey = 'state';
  static int? _bootstrapBackgroundColorArgb;

  static int? get bootstrapBackgroundColorArgb => _bootstrapBackgroundColorArgb;

  bool _inited = false;
  Box<Map<dynamic, dynamic>>? _box;

  Future<void> init() async {
    if (_inited) return;
    _box = await Hive.openBox<Map<dynamic, dynamic>>(_boxName);
    _inited = true;
  }

  Future<PlaybackCacheState?> load() async {
    await init();
    final Map<dynamic, dynamic>? raw = _box!.get(_stateKey);
    return PlaybackCacheState.fromMap(raw);
  }

  Future<int?> loadBackgroundColorArgb() async {
    await init();
    final Map<dynamic, dynamic>? raw = _box!.get(_stateKey);
    final int? value = raw == null
        ? null
        : int.tryParse(raw['backgroundColorArgb']?.toString() ?? '');
    if (value != null) {
      _bootstrapBackgroundColorArgb = value;
    }
    return value;
  }

  Future<void> primeBootstrapBackgroundColor() async {
    await loadBackgroundColorArgb();
  }

  Future<void> saveBackgroundColorArgb(int argb) async {
    await init();
    final Map<dynamic, dynamic> raw = Map<dynamic, dynamic>.from(
      _box!.get(_stateKey) ?? <dynamic, dynamic>{},
    );
    raw['backgroundColorArgb'] = argb;
    _bootstrapBackgroundColorArgb = argb;
    await _box!.put(_stateKey, raw);
  }

  Future<void> save(PlaybackCacheState state) async {
    await init();
    if (state.queueSongs.isEmpty) {
      await clear();
      return;
    }
    if (state.backgroundColorArgb != null) {
      _bootstrapBackgroundColorArgb = state.backgroundColorArgb;
    }
    await _box!.put(_stateKey, state.toMap());
  }

  Future<void> clear() async {
    await init();
    await _box!.delete(_stateKey);
  }
}
