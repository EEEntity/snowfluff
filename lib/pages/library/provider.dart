// 提供个人音乐库
// 歌单第一个是喜欢的音乐，后续按顺序是用户创建的歌单，最后是收藏的歌单
// 使用每个UserPlaylistPlaylist的userId区分用户创建的歌单和收藏的歌单

import 'dart:async';
import 'package:snowfluff/common/local_proxy_service.dart';
import 'package:snowfluff/common/media_cache_service.dart';
import 'package:snowfluff/common/user_info_store.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ncm_api/api/agent.dart';
import 'package:ncm_api/api/user.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'provider.g.dart';

// 用户数据
class UserData {
  String nickname; // 用户昵称
  String avatarUrl; // 用户头像
  UserData({required this.nickname, required this.avatarUrl});
}

// 音乐库歌单数据，不包含歌单内的歌曲数据
class LibraryPlaylistData {
  int id; // 歌单id
  String name; // 歌单名称
  String coverUrl; // 歌单封面
  int coverImgId; // 封面图片id
  int trackCount; // 歌曲数量
  int creatorId; // 创建者id，区分用户创建的歌单和收藏的歌单
  int specialType; // 5表示喜欢的音乐
  String description; // 歌单简介
  LibraryPlaylistData({
    required this.id,
    required this.name,
    required this.coverUrl,
    required this.coverImgId,
    required this.trackCount,
    required this.creatorId,
    required this.specialType,
    required this.description,
  });

  Map<String, dynamic> toCacheMap() {
    return <String, dynamic>{
      'id': id.toString(),
      'name': name,
      'coverUrl': coverUrl,
      'coverImgId': coverImgId.toString(),
      'trackCount': trackCount,
      'creatorId': creatorId.toString(),
      'specialType': specialType,
      'description': description,
    };
  }

  factory LibraryPlaylistData.fromCacheMap(Map<dynamic, dynamic> map) {
    return LibraryPlaylistData(
      id: int.tryParse(map['id'].toString()) ?? 0,
      name: map['name']?.toString() ?? '',
      coverUrl: map['coverUrl']?.toString() ?? '',
      coverImgId: int.tryParse(map['coverImgId'].toString()) ?? 0,
      trackCount: int.tryParse(map['trackCount'].toString()) ?? 0,
      creatorId: int.tryParse(map['creatorId'].toString()) ?? 0,
      specialType: int.tryParse(map['specialType'].toString()) ?? 0,
      description: map['description']?.toString() ?? '',
    );
  }
}

extension CacheKeepAlive on Ref {
  // 数据延迟销毁
  void cacheFor(Duration duration) {
    final link = keepAlive();
    Timer? disposeTimer;
    onDispose(() => disposeTimer?.cancel());
    onCancel(() {
      disposeTimer = Timer(duration, () {
        link.close();
      });
    });
    onResume(() => disposeTimer?.cancel());
  }
}

@riverpod
Future<UserData> userData(Ref ref) async {
  ref.cacheFor(const Duration(minutes: 10));
  final userInfoStore = UserInfoStore();
  final cached = await userInfoStore.read();

  if (cached != null) {
    unawaited(
      _refreshUserInfoInBackground(
        ref: ref,
        userInfoStore: userInfoStore,
        current: cached,
      ),
    );
    return UserData(nickname: cached.nickname, avatarUrl: cached.avatarUrl);
  }

  try {
    final fresh = await SnowfluffMusicManager().userInfo().timeout(
      const Duration(seconds: 5),
    );
    final profile = fresh?.profile;
    if (profile == null || profile.userId <= 0) {
      return UserData(nickname: 'Ghost', avatarUrl: '');
    }
    await userInfoStore.saveFromProfile(profile);
    return UserData(nickname: profile.nickname, avatarUrl: profile.avatarUrl);
  } catch (_) {
    return UserData(nickname: 'Ghost', avatarUrl: '');
  }
}

@riverpod
Future<List<LibraryPlaylistData>> libraryPlaylistData(Ref ref) async {
  ref.cacheFor(const Duration(minutes: 10));
  final MediaCacheService cacheService = MediaCacheService();
  final UserInfoStore userInfoStore = UserInfoStore();
  final int uid = await _currentUid(userInfoStore);
  final List<LibraryPlaylistData> cachedPlaylists = uid > 0
      ? await _loadLibraryPlaylistsFromCache(cacheService, uid)
      : const <LibraryPlaylistData>[];

  try {
    if (uid > 0) {
      if (cachedPlaylists.isNotEmpty) {
        unawaited(
          _refreshLibraryPlaylistsInBackground(
            ref: ref,
            cacheService: cacheService,
            uid: uid,
            cachedPlaylists: cachedPlaylists,
          ),
        );
        return cachedPlaylists;
      }

      final List<LibraryPlaylistData> fresh = await _fetchLibraryPlaylists(uid);
      if (fresh.isNotEmpty) {
        await cacheService.saveLibraryPlaylists(
          uid: uid,
          playlists: fresh.map((e) => e.toCacheMap()).toList(growable: false),
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
      }
      return fresh;
    }

    return cachedPlaylists;
  } catch (_) {
    return cachedPlaylists;
  }
}

final likedPlaylistPreviewProvider =
    FutureProvider.family<List<MediaItem>, int>((
      Ref ref,
      int playlistId,
    ) async {
      if (playlistId <= 0) return const <MediaItem>[];
      final MediaCacheService cacheService = MediaCacheService();
      final List<Map<dynamic, dynamic>> songs = await cacheService
          .loadLikedPreviewSongs(playlistId);
      if (songs.isEmpty) return const <MediaItem>[];
      return songs
          .take(12)
          .map(_cachedSongToMediaItem)
          .where((MediaItem e) => e.id.isNotEmpty)
          .toList(growable: false);
    });

Future<int> _currentUid(UserInfoStore userInfoStore) async {
  final cachedUid = await userInfoStore.readUid();
  if (cachedUid > 0) return cachedUid;

  try {
    final fresh = await SnowfluffMusicManager().userInfo().timeout(
      const Duration(seconds: 5),
    );
    final profile = fresh?.profile;
    if (profile == null || profile.userId <= 0) return 0;
    await userInfoStore.saveFromProfile(profile);
    return profile.userId;
  } catch (_) {
    return 0;
  }
}

Future<List<LibraryPlaylistData>> _loadLibraryPlaylistsFromCache(
  MediaCacheService cacheService,
  int uid,
) async {
  final List<Map<dynamic, dynamic>> cached = await cacheService
      .loadLibraryPlaylists(uid);
  if (cached.isEmpty) return const <LibraryPlaylistData>[];
  return cached
      .map(LibraryPlaylistData.fromCacheMap)
      .where((LibraryPlaylistData e) => e.id > 0)
      .toList(growable: false);
}

LibraryPlaylistData _toLibraryPlaylistData(UserPlaylistPlaylist playlist) {
  final String imageIdentity = playlist.coverImgId > 0
      ? playlist.coverImgId.toString()
      : MediaCacheService.safeImageIdentityFromUrl(playlist.coverImgUrl);
  final String coverUrl = LocalProxyService.proxyImageUrl(
    playlist.coverImgUrl,
    pid: imageIdentity.isEmpty ? null : imageIdentity,
  );

  return LibraryPlaylistData(
    id: playlist.id,
    name: playlist.name,
    coverUrl: coverUrl,
    coverImgId: playlist.coverImgId,
    trackCount: playlist.trackCount,
    creatorId: playlist.userId,
    specialType: playlist.specialType,
    description: playlist.description,
  );
}

MediaItem _cachedSongToMediaItem(Map<dynamic, dynamic> map) {
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

Future<List<LibraryPlaylistData>> _fetchLibraryPlaylists(
  int uid,
) async {
  final result = await SnowfluffMusicManager()
      .userPlaylist(uid: '$uid')
      .timeout(const Duration(seconds: 5));
  return result?.playlist.map(_toLibraryPlaylistData).toList(growable: false) ??
      const <LibraryPlaylistData>[];
}

Future<void> _refreshLibraryPlaylistsInBackground({
  required Ref ref,
  required MediaCacheService cacheService,
  required int uid,
  required List<LibraryPlaylistData> cachedPlaylists,
}) async {
  try {
    final List<LibraryPlaylistData> fresh = await _fetchLibraryPlaylists(uid);
    if (_sameLibraryPlaylists(cachedPlaylists, fresh)) {
      return;
    }
    await cacheService.saveLibraryPlaylists(
      uid: uid,
      playlists: fresh.map((e) => e.toCacheMap()).toList(growable: false),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    ref.invalidateSelf();
  } catch (_) {}
}

Future<void> _refreshUserInfoInBackground({
  required Ref ref,
  required UserInfoStore userInfoStore,
  required CachedUserInfo current,
}) async {
  try {
    final fresh = await SnowfluffMusicManager().userInfo().timeout(
      const Duration(seconds: 5),
    );
    final profile = fresh?.profile;
    if (profile == null || profile.userId <= 0) return;

    final next = CachedUserInfo.fromProfile(profile);
    if (current.sameCore(next)) return;

    await userInfoStore.save(next);
    ref.invalidateSelf();
  } catch (_) {}
}

bool _sameLibraryPlaylists(
  List<LibraryPlaylistData> a,
  List<LibraryPlaylistData> b,
) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    final LibraryPlaylistData x = a[i];
    final LibraryPlaylistData y = b[i];
    if (x.id != y.id) return false;
    if (x.name != y.name) return false;
    if (x.coverImgId != y.coverImgId) return false;
    if (x.trackCount != y.trackCount) return false;
    if (x.creatorId != y.creatorId) return false;
    if (x.specialType != y.specialType) return false;
    if (x.description != y.description) return false;
  }
  return true;
}
