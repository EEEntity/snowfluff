import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:snowfluff/common/local_proxy_service.dart';
import 'package:snowfluff/common/media_cache_service.dart';
import 'package:ncm_api/api/agent.dart';
import 'package:ncm_api/api/playlist.dart';
import 'package:ncm_api/api/song.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'provider.g.dart';

class PlaylistData {
  String title; // 歌单标题
  String description; // 歌单描述
  // 歌单创建者
  // 最后更新时间
  bool isPrivate; // 是否私密
  String coverUrl; // 歌单封面URL
  List<MediaItem> medias; // 歌单中的媒体项列表，顺便歌单长度
  PlaylistData(
    this.title,
    this.description,
    this.isPrivate,
    this.coverUrl,
    this.medias,
  );
}

@riverpod
Future<PlaylistData> playlistDetail(Ref ref, int id) async {
  final link = ref.keepAlive();
  Timer? disposeTimer;
  ref.onDispose(() => disposeTimer?.cancel());
  ref.onCancel(() {
    disposeTimer = Timer(const Duration(minutes: 10), () {
      link.close();
    });
  });
  ref.onResume(() => disposeTimer?.cancel());

  final result = await SnowfluffMusicManager().playlistDetail(id: id);
  final playlist = result?.playlist;
  if (playlist == null) {
    return PlaylistData('', '', false, '', []);
  }

  // 使用 trackIds 获取完整歌曲 ID 列表，避免 tracks 只返回前20首的问题
  // https://github.com/Binaryify/NeteaseCloudMusicApi/issues/452
  final allIds = playlist.trackIds.map((t) => t.id).toList(growable: false);

  // 并行批量请求歌曲详情（每批最多1000首）
  final futures = <Future<SongDetailEntity?>>[];
  for (int i = 0; i < allIds.length; i += 1000) {
    futures.add(SnowfluffMusicManager().songDetail(
      ids: allIds.sublist(i, (i + 1000).clamp(0, allIds.length)),
    ));
  }
  final batchResults = await Future.wait(futures);

  final List<SongDetailSongs> allSongs = [];
  final List<SongDetailPrivileges> allPrivileges = [];
  for (final songResult in batchResults) {
    if (songResult != null) {
      allSongs.addAll(songResult.songs);
      allPrivileges.addAll(songResult.privileges);
    }
  }

  final medias = _buildPlaylistData(allSongs, allPrivileges);
  final PlaylistData data = PlaylistData(
    playlist.name,
    playlist.description,
    playlist.privacy == 10 ? true : false, // 0公开歌单，10私密歌单
    playlist.coverImgUrl,
    medias,
  );

  unawaited(
    _cachePlaylistForLibraryScope(
      playlistId: id,
      playlist: playlist,
      medias: medias,
    ),
  );

  return data;
}

List<MediaItem> _buildPlaylistData(
  List<SongDetailSongs> tracks,
  List<SongDetailPrivileges> privileges,
) {
  // assert (tracks.length == privileges.length);
  final int len = tracks.length;
  final List<MediaItem> out = List<MediaItem>.generate(len, (i) {
    final t = tracks[i];
    final p = privileges[i];
    final picUrl = t.al?.picUrl ?? '';
    final String proxyUrl = LocalProxyService.proxyImageUrl(
      picUrl,
      pid: t.al?.pic.toString(),
    );
    return MediaItem(
      id: t.id.toString(),
      title: t.name,
      duration: Duration(milliseconds: t.dt),
      artist: t.ar.map((artist) => artist.name).toList().join(' / '),
      artUri: Uri.parse(proxyUrl),
      extras: {
        'isGrey': p.st < 0, // st<0表示歌曲不可用，灰色显示
        'plLevel': p.plLevel, // 当前最高试听音质
        'maxBrLevel': p.maxBrLevel, // 歌曲最高音质
        'artistIds': t.ar.map((artist) => artist.id).toList(growable: false),
      },
    );
  }, growable: false);
  return out;
}

Future<void> _cachePlaylistForLibraryScope({
  required int playlistId,
  required PlaylistDetailPlaylist playlist,
  required List<MediaItem> medias,
}) async {
  if (playlistId <= 0) return;
  final MediaCacheService cacheService = MediaCacheService();

  final bool isLibraryPlaylist = await cacheService.isLibraryPlaylistId(
    playlistId,
  );
  if (!isLibraryPlaylist) return;

  final String imageIdentity = playlist.coverImgId > 0
      ? playlist.coverImgId.toString()
      : MediaCacheService.safeImageIdentityFromUrl(playlist.coverImgUrl);
  final String coverCacheKey = MediaCacheService.makeImageCacheKey(
    identity: imageIdentity,
    width: 500,
    height: 500,
    variant: 'playlist_cover',
  );

  await cacheService.savePlaylistSnapshot(
    PlaylistSnapshot(
      playlistId: playlistId,
      description: playlist.description,
      coverCacheKey: coverCacheKey,
      coverWidth: 500,
      coverHeight: 500,
      songIds: medias
          .map((MediaItem e) => int.tryParse(e.id) ?? 0)
          .where((int id) => id > 0)
          .toList(growable: false),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  );

  final bool isLikedPlaylist = await cacheService.isLikedPlaylistId(playlistId);
  if (!isLikedPlaylist) return;

  final List<Map<String, dynamic>> previewSongs = medias
      .take(12)
      .map(
        (MediaItem e) => <String, dynamic>{
          'id': e.id,
          'title': e.title,
          'artist': e.artist ?? '',
          'artUri': e.artUri?.toString() ?? '',
          'durationMs': e.duration?.inMilliseconds ?? 0,
        },
      )
      .toList(growable: false);

  await cacheService.saveLikedPreviewSongs(
    playlistId: playlistId,
    songs: previewSongs,
    updatedAtMs: DateTime.now().millisecondsSinceEpoch,
  );
}
