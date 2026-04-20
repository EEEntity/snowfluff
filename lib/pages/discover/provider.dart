import 'dart:async';
import 'package:snowfluff/common/local_proxy_service.dart';
import 'package:snowfluff/common/media_cache_service.dart';
import 'package:snowfluff/common/music_handler.dart';
import 'package:audio_service/audio_service.dart';
import 'package:ncm_api/api/agent.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'provider.g.dart';

class RecommendPlaylistCardData {
  final int id; // 歌单id
  final String title; // 歌单标题
  final String coverUrl; // 歌单封面URL
  const RecommendPlaylistCardData({
    required this.id,
    required this.title,
    required this.coverUrl,
  });
}

// 每日推荐歌曲MediaItem列表
@riverpod
Future<List<MediaItem>> songs(Ref ref) async {
  _cacheFor(ref, const Duration(minutes: 10));
  final MediaCacheService cacheService = MediaCacheService();
  final String todayKey = _dailyCacheKey(DateTime.now());
  final List<MediaItem> cachedSongs = await _loadCachedSongs(
    cacheService,
    todayKey,
  );
  if (cachedSongs.isNotEmpty) {
    final int? updatedAtMs = await cacheService.loadDailyRecommendSongsUpdatedAtMs(
      todayKey,
    );
    if (_shouldRefreshForShanghai0600(updatedAtMs)) {
      unawaited(
        _refreshSongsInBackground(
          ref: ref,
          cacheService: cacheService,
          todayKey: todayKey,
          cachedSongs: cachedSongs,
        ),
      );
    }
    return cachedSongs;
  }

  final List<MediaItem> freshSongs = await _fetchSongsFromApi();
  if (freshSongs.isNotEmpty) {
    await cacheService.saveDailyRecommendSongs(
      dateKey: todayKey,
      songs: freshSongs.map(_songToCacheMap).toList(growable: false),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }
  return freshSongs;
}

// 每日推荐歌单卡片数据
@riverpod
Future<List<RecommendPlaylistCardData>> recommendPlaylists(Ref ref) async {
  _cacheFor(ref, const Duration(minutes: 10));
  final MediaCacheService cacheService = MediaCacheService();
  final List<RecommendPlaylistCardData> cachedPlaylists =
      await _loadCachedRecommendPlaylists(cacheService);
  if (cachedPlaylists.isNotEmpty) {
    final int? updatedAtMs =
        await cacheService.loadDiscoverRecommendPlaylistsUpdatedAtMs();
    if (_shouldRefreshForShanghai0600(updatedAtMs)) {
      unawaited(
        _refreshRecommendPlaylistsInBackground(
          ref: ref,
          cacheService: cacheService,
          cachedPlaylists: cachedPlaylists,
        ),
      );
    }
    return cachedPlaylists;
  }

  final List<RecommendPlaylistCardData> freshPlaylists =
      await _fetchRecommendPlaylistsFromApi();
  if (freshPlaylists.isNotEmpty) {
    await cacheService.saveDiscoverRecommendPlaylists(
      playlists: freshPlaylists
          .map(_recommendPlaylistToCacheMap)
          .toList(growable: false),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }
  return freshPlaylists;
}

void _cacheFor(Ref ref, Duration duration) {
  final link = ref.keepAlive();
  Timer? disposeTimer;
  ref.onDispose(() => disposeTimer?.cancel());
  ref.onCancel(() {
    disposeTimer = Timer(duration, () {
      link.close();
    });
  });
  ref.onResume(() => disposeTimer?.cancel());
}

Future<List<MediaItem>> _loadCachedSongs(
  MediaCacheService cacheService,
  String todayKey,
) async {
  final List<Map<dynamic, dynamic>> raw = await cacheService
      .loadDailyRecommendSongs(todayKey);
  if (raw.isEmpty) return const <MediaItem>[];
  return raw.map(_songFromCacheMap).toList(growable: false);
}

Future<List<MediaItem>> _fetchSongsFromApi() async {
  try {
    final recommendSongs = await SnowfluffMusicManager()
        .recommendSongs()
        .timeout(const Duration(seconds: 5));
    return recommendSongs?.data?.dailySongs
            .map(
              (song) => MediaItem(
                id: song.id.toString(),
                title: song.name,
                duration: Duration(milliseconds: song.dt),
                artist: song.ar.map((e) => e.name).toList().join(' / '),
                artUri: Uri.parse(_buildSongArtProxyUrl(song.id, song.al?.picUrl ?? '')),
                extras: <String, dynamic>{
                  'artistIds': song.ar.map((e) => e.id).toList(growable: false),
                },
              ),
            )
            .toList(growable: false) ??
        const <MediaItem>[];
  } catch (_) {
    return const <MediaItem>[];
  }
}

Future<void> _refreshSongsInBackground({
  required Ref ref,
  required MediaCacheService cacheService,
  required String todayKey,
  required List<MediaItem> cachedSongs,
}) async {
  try {
    final List<MediaItem> freshSongs = await _fetchSongsFromApi();
    if (freshSongs.isEmpty || _sameSongs(cachedSongs, freshSongs)) {
      return;
    }
    await cacheService.saveDailyRecommendSongs(
      dateKey: todayKey,
      songs: freshSongs.map(_songToCacheMap).toList(growable: false),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    ref.invalidateSelf();
  } catch (_) {
    // Ignore background refresh error
  }
}

Future<List<RecommendPlaylistCardData>> _loadCachedRecommendPlaylists(
  MediaCacheService cacheService,
) async {
  final List<Map<dynamic, dynamic>> raw = await cacheService
      .loadDiscoverRecommendPlaylists();
  if (raw.isEmpty) return const <RecommendPlaylistCardData>[];
  return raw
      .map(_recommendPlaylistFromCacheMap)
      .where((RecommendPlaylistCardData e) => e.id > 0)
      .toList(growable: false);
}

Future<List<RecommendPlaylistCardData>> _fetchRecommendPlaylistsFromApi() async {
  try {
    final recommendResource = await SnowfluffMusicManager()
        .recommendResource()
        .timeout(const Duration(seconds: 5));
    return recommendResource?.recommend
            .map(
              (playlist) => RecommendPlaylistCardData(
                id: playlist.id,
                title: playlist.name,
                coverUrl: _buildPlaylistCoverProxyUrl(
                  playlist.id,
                  playlist.picUrl,
                ),
              ),
            )
            .toList(growable: false) ??
        const <RecommendPlaylistCardData>[];
  } catch (_) {
    return const <RecommendPlaylistCardData>[];
  }
}

Future<void> _refreshRecommendPlaylistsInBackground({
  required Ref ref,
  required MediaCacheService cacheService,
  required List<RecommendPlaylistCardData> cachedPlaylists,
}) async {
  try {
    final List<RecommendPlaylistCardData> freshPlaylists =
        await _fetchRecommendPlaylistsFromApi();
    if (freshPlaylists.isEmpty ||
        _sameRecommendPlaylists(cachedPlaylists, freshPlaylists)) {
      return;
    }
    await cacheService.saveDiscoverRecommendPlaylists(
      playlists: freshPlaylists
          .map(_recommendPlaylistToCacheMap)
          .toList(growable: false),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    ref.invalidateSelf();
  } catch (_) {
    // Ignore background refresh error
  }
}

Map<String, dynamic> _songToCacheMap(MediaItem item) {
  return <String, dynamic>{
    'id': item.id,
    'title': item.title,
    'artist': item.artist ?? '',
    'durationMs': item.duration?.inMilliseconds ?? 0,
    'artUri': item.artUri?.toString() ?? '',
    'artistIds': item.extras?['artistIds'] ?? const <int>[],
  };
}

MediaItem _songFromCacheMap(Map<dynamic, dynamic> map) {
  final String art = map['artUri']?.toString() ?? '';
  final int durationMs = int.tryParse(map['durationMs'].toString()) ?? 0;
  final List<int> artistIds = map['artistIds'] is List
  ? (map['artistIds'] as List)
    .map((e) => int.tryParse(e.toString()) ?? 0)
    .where((id) => id > 0)
    .toList(growable: false)
  : const <int>[];
  return MediaItem(
    id: map['id']?.toString() ?? '',
    title: map['title']?.toString() ?? '',
    artist: map['artist']?.toString() ?? '',
    duration: Duration(milliseconds: durationMs),
    artUri: art.isEmpty ? null : Uri.parse(art),
    extras: <String, dynamic>{
      'artistIds': artistIds,
    },
  );
}

Map<String, dynamic> _recommendPlaylistToCacheMap(
  RecommendPlaylistCardData item,
) {
  return <String, dynamic>{
    'id': item.id.toString(),
    'title': item.title,
    'coverUrl': item.coverUrl,
  };
}

RecommendPlaylistCardData _recommendPlaylistFromCacheMap(
  Map<dynamic, dynamic> map,
) {
  return RecommendPlaylistCardData(
    id: int.tryParse(map['id'].toString()) ?? 0,
    title: map['title']?.toString() ?? '',
    coverUrl: map['coverUrl']?.toString() ?? '',
  );
}

bool _sameSongs(List<MediaItem> a, List<MediaItem> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    final MediaItem x = a[i];
    final MediaItem y = b[i];
    if (x.id != y.id) return false;
    if (x.title != y.title) return false;
    if ((x.artist ?? '') != (y.artist ?? '')) return false;
    if ((x.duration?.inMilliseconds ?? 0) != (y.duration?.inMilliseconds ?? 0)) {
      return false;
    }
  }
  return true;
}

bool _sameRecommendPlaylists(
  List<RecommendPlaylistCardData> a,
  List<RecommendPlaylistCardData> b,
) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    final RecommendPlaylistCardData x = a[i];
    final RecommendPlaylistCardData y = b[i];
    if (x.id != y.id) return false;
    if (x.title != y.title) return false;
  }
  return true;
}

String _dailyCacheKey(DateTime dateTime) {
  final DateTime businessDay = _shanghaiBusinessDay(dateTime);
  final String y = businessDay.year.toString().padLeft(4, '0');
  final String m = businessDay.month.toString().padLeft(2, '0');
  final String d = businessDay.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

bool _shouldRefreshForShanghai0600(int? updatedAtMs) {
  // 用Asia/Shanghai时区06:00作为更新临界时间
  if (updatedAtMs == null || updatedAtMs <= 0) return true;
  final DateTime now = DateTime.now();
  final DateTime updatedAt = DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
  final DateTime nowDay = _shanghaiBusinessDay(now);
  final DateTime updatedDay = _shanghaiBusinessDay(updatedAt);
  return nowDay.year != updatedDay.year ||
      nowDay.month != updatedDay.month ||
      nowDay.day != updatedDay.day;
}

DateTime _shanghaiBusinessDay(DateTime instant) {
  final DateTime shanghaiNow = instant.toUtc().add(const Duration(hours: 8));
  final DateTime effective = shanghaiNow.hour < 6
      ? shanghaiNow.subtract(const Duration(days: 1))
      : shanghaiNow;
  return DateTime(effective.year, effective.month, effective.day);
}

String _buildSongArtProxyUrl(int songId, String rawUrl) {
  if (rawUrl.isEmpty) return '';
  final String identity = songId > 0
      ? songId.toString()
      : MediaCacheService.safeImageIdentityFromUrl(rawUrl);
  return LocalProxyService.proxyImageUrl(
    rawUrl,
    pid: identity,
  );
}

String _buildPlaylistCoverProxyUrl(int playlistId, String rawUrl) {
  if (rawUrl.isEmpty) return '';
  final String identity = playlistId > 0
      ? playlistId.toString()
      : MediaCacheService.safeImageIdentityFromUrl(rawUrl);
  return LocalProxyService.proxyImageUrl(
    rawUrl,
    pid: identity,
  );
}

// 进入私人FM模式
@riverpod
Future<void> enterPersonalFM(Ref ref) async {
  await SnowfluffMusicHandler().enterFMMode();
}
