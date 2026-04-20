import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:ncm_api/api/agent.dart';
import 'package:ncm_api/api/artist.dart';
import 'package:ncm_api/api/song.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'provider.g.dart';

const int kArtistAlbumPageSize = 20;
const _artistCacheTtl = Duration(minutes: 10);

class ArtistInfoData {
  final String name; // 艺术家名称
  final String picUrl; // 艺术家图片URL（来自artistAlbums接口）
  final String briefDesc; // 艺术家简介
  final int musicSize; // 歌曲总数
  final int albumSize; // 专辑总数
  const ArtistInfoData({
    required this.name,
    required this.picUrl,
    required this.briefDesc,
    required this.musicSize,
    required this.albumSize,
  });
  const ArtistInfoData.empty()
      : name = '',
        picUrl = '',
        briefDesc = '',
        musicSize = 0,
        albumSize = 0;
}

class ArtistAlbumCardData {
  final int id; // 专辑ID
  final String name; // 专辑名称(用于卡片标题)
  final String picUrl; // 专辑图片(用于卡片封面)
  final int publishTime; // 专辑发布时间(用于卡片副标题)
  ArtistAlbumCardData({
    required this.id,
    required this.name,
    required this.picUrl,
    required this.publishTime,
  });
}

/// 复用首屏专辑请求，避免artistInfo和artistAllAlbumIds重复用offset=0的接口
@riverpod
Future<ArtistAlbumsEntity?> artistAlbumsFirstPage(Ref ref, int id) async {
  final manager = SnowfluffMusicManager();
  return manager.artistAlbums(
    id: id,
    offset: 0,
    limit: kArtistAlbumPageSize,
    total: true,
  );
}

/// 第一部分：歌手基础信息(含总歌曲/总专辑)
@riverpod
Future<ArtistInfoData> artistInfo(Ref ref, int id) async {
  final link = ref.keepAlive();
  Timer? disposeTimer;
  void startDisposeTimer() {
    disposeTimer?.cancel();
    disposeTimer = Timer(const Duration(minutes: 10), link.close);
  }
  ref.onCancel(startDisposeTimer);
  ref.onResume(() => disposeTimer?.cancel());
  ref.onDispose(() => disposeTimer?.cancel());
  final manager = SnowfluffMusicManager();
  final results = await Future.wait([
    ref.watch(artistAlbumsFirstPageProvider(id).future),
    manager.artistDetail(id: id),
  ]);
  final albumsEntity = results[0] as ArtistAlbumsEntity?;
  final descEntity = results[1] as ArtistDescriptionEntity?;
  final artist = albumsEntity?.artist;
  if (artist == null) return const ArtistInfoData.empty();
  return ArtistInfoData(
    name: artist.name,
    picUrl: artist.picUrl,
    briefDesc: descEntity?.briefDesc ?? '',
    musicSize: artist.musicSize,
    albumSize: artist.albumSize,
  );
}

/// 第二部分：热门50首歌曲(MediaItem)
@riverpod
Future<List<MediaItem>> artistTopMedias(Ref ref, int id) async {
  final link = ref.keepAlive();
  Timer? disposeTimer;
  void startDisposeTimer() {
    disposeTimer?.cancel();
    disposeTimer = Timer(const Duration(minutes: 10), link.close);
  }
  ref.onCancel(startDisposeTimer);
  ref.onResume(() => disposeTimer?.cancel());
  ref.onDispose(() => disposeTimer?.cancel());
  final manager = SnowfluffMusicManager();
  final topSongsEntity = await manager.artistTopSongs(id: id);
  final orderedSongIds = _extractTopSongIds(topSongsEntity);
  if (orderedSongIds.isEmpty) return const <MediaItem>[];
  return _buildTopMedias(
    manager: manager,
    orderedSongIds: orderedSongIds,
  );
}

/// 第三部分：全量专辑ID(按页拉取后合并)
/// 返回轻量`List<int>`，页面可直接按需用专辑详情provider做展示
@riverpod
Future<List<int>> artistAllAlbumIds(Ref ref, int id) async {
  final link = ref.keepAlive();
  Timer? disposeTimer;
  void startDisposeTimer() {
    disposeTimer?.cancel();
    disposeTimer = Timer(const Duration(minutes: 10), link.close);
  }
  ref.onCancel(startDisposeTimer);
  ref.onResume(() => disposeTimer?.cancel());
  ref.onDispose(() => disposeTimer?.cancel());
  final manager = SnowfluffMusicManager();
  // 先复用首屏请求
  final firstPage = await ref.watch(artistAlbumsFirstPageProvider(id).future);
  final firstIds = _extractAlbumIds(firstPage);
  final totalFromFirst = firstPage?.artist?.albumSize ?? 0;
  if (firstIds.isEmpty) return const <int>[];
  // 去重并保序，防止接口偶发重复
  final out = <int>[];
  final seen = <int>{};
  for (final id in firstIds) {
    if (seen.add(id)) out.add(id);
  }
  if (totalFromFirst > 0 && out.length >= totalFromFirst) {
    return List<int>.unmodifiable(out);
  }
  var offset = firstIds.length;
  while (true) {
    final page = await manager.artistAlbums(
      id: id,
      offset: offset,
      limit: kArtistAlbumPageSize,
      total: true,
    );
    final pageIds = _extractAlbumIds(page);
    if (pageIds.isEmpty) break;
    for (final albumId in pageIds) {
      if (seen.add(albumId)) out.add(albumId);
    }
    offset += pageIds.length;
    final total = page?.artist?.albumSize ?? totalFromFirst;
    if (total > 0 && out.length >= total) break;
    if (pageIds.length < kArtistAlbumPageSize) break;
  }
  return List<int>.unmodifiable(out);
}

Future<List<MediaItem>> _buildTopMedias({
  required SnowfluffMusicManager manager,
  required List<int> orderedSongIds,
}) async {
  final detail = await manager.songDetail(ids: orderedSongIds);
  final songs = detail?.songs ?? const <SongDetailSongs>[];
  if (songs.isEmpty) return const <MediaItem>[];
  // O(n)建索引，避免线性查找
  // 或许可以进一步优化
  final songById = <int, SongDetailSongs>{
    for (final s in songs) s.id: s,
  };
  final privilegeById = <int, SongDetailPrivileges>{
    for (final p in (detail?.privileges ?? const <SongDetailPrivileges>[])) p.id: p,
  };
  final out = <MediaItem>[];
  for (final id in orderedSongIds) {
    final s = songById[id];
    if (s == null) continue;
    final p = privilegeById[id];
    final picUrl = s.al?.picUrl ?? '';
    out.add(
      MediaItem(
        id: s.id.toString(),
        title: s.name,
        duration: Duration(milliseconds: s.dt),
        artist: s.ar.map((a) => a.name).join(' / '),
        artUri: Uri.parse(
          'http://127.0.0.1:8848/image?url=${Uri.encodeComponent(picUrl)}',
        ),
        extras: {
          'isGrey': (p?.st ?? 0) < 0,
          'plLevel': p?.plLevel ?? '',
          'maxBrLevel': p?.maxBrLevel ?? '',
          'artistIds': s.ar.map((a) => a.id).toList(growable: false),
        },
      ),
    );
  }
  return List<MediaItem>.unmodifiable(out);
}

List<int> _extractTopSongIds(ArtistTopSongsEntity? entity) {
  final songs = entity?.songs ?? const <ArtistTopSongSong>[];
  if (songs.isEmpty) return const <int>[];
  final seen = <int>{};
  final ids = <int>[];
  for (final s in songs) {
    final id = s.id;
    if (id > 0 && seen.add(id)) ids.add(id);
  }
  return List<int>.unmodifiable(ids);
}

List<int> _extractAlbumIds(ArtistAlbumsEntity? entity) {
  final albums = entity?.hotAlbums ?? const <ArtistAlbumsAlbum>[];
  if (albums.isEmpty) return const <int>[];
  final ids = <int>[];
  for (final a in albums) {
    final id = a.id;
    if (id > 0) ids.add(id);
  }
  return List<int>.unmodifiable(ids);
}

@riverpod
Future<List<ArtistAlbumCardData>> artistAlbumCards(Ref ref, int id) async {
  _keepAliveForArtistPage(ref);
  final manager = SnowfluffMusicManager();
  final firstPage = await ref.watch(artistAlbumsFirstPageProvider(id).future);
  final out = <ArtistAlbumCardData>[];
  final seen = <int>{};
  void appendFromPage(ArtistAlbumsEntity? page) {
    final albums = page?.hotAlbums ?? const <ArtistAlbumsAlbum>[];
    for (final a in albums) {
      if (a.id <= 0 || !seen.add(a.id)) continue;
      out.add(
        ArtistAlbumCardData(
          id: a.id,
          name: a.name,
          picUrl: a.picUrl,
          publishTime: a.publishTime,
        ),
      );
    }
  }
  appendFromPage(firstPage);
  if (out.isEmpty) return const <ArtistAlbumCardData>[];
  final totalFromFirst = firstPage?.artist?.albumSize ?? 0;
  var offset = firstPage?.hotAlbums.length ?? 0;
  while (true) {
    final page = await manager.artistAlbums(
      id: id,
      offset: offset,
      limit: kArtistAlbumPageSize,
      total: true,
    );
    final pageAlbums = page?.hotAlbums ?? const <ArtistAlbumsAlbum>[];
    if (pageAlbums.isEmpty) break;
    appendFromPage(page);
    offset += pageAlbums.length;
    final total = page?.artist?.albumSize ?? totalFromFirst;
    if (total > 0 && out.length >= total) break;
    if (pageAlbums.length < kArtistAlbumPageSize) break;
  }
  return List<ArtistAlbumCardData>.unmodifiable(out);
}

void _keepAliveForArtistPage(Ref ref) {
  final link = ref.keepAlive();
  Timer? disposeTimer;

  void startDisposeTimer() {
    disposeTimer?.cancel();
    disposeTimer = Timer(_artistCacheTtl, link.close);
  }

  ref.onCancel(startDisposeTimer);
  ref.onResume(() => disposeTimer?.cancel());
  ref.onDispose(() => disposeTimer?.cancel());
}
