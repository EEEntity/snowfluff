import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:ncm_api/api/agent.dart';
import 'package:ncm_api/api/search.dart';
import 'package:ncm_api/api/song.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'provider.g.dart';

const _searchCacheTtl = Duration(minutes: 1);
const _searchSongLimit = 20;

class SearchAlbumCardData {
  final int id;
  final String name;
  final String coverUrl;
  final String artistNames;

  const SearchAlbumCardData({
    required this.id,
    required this.name,
    required this.coverUrl,
    required this.artistNames,
  });
}

class SearchArtistCardData {
  final int id;
  final String name;
  final String avatarUrl;
  final String subtitle;

  const SearchArtistCardData({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.subtitle,
  });
}

class SearchPlaylistCardData {
  final int id;
  final String title;
  final String coverUrl;
  final String subtitle;

  const SearchPlaylistCardData({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.subtitle,
  });
}

extension _CacheKeepAlive on Ref {
  void cacheFor(Duration duration) {
    final link = keepAlive();
    Timer? disposeTimer;

    onCancel(() {
      disposeTimer?.cancel();
      disposeTimer = Timer(duration, link.close);
    });
    onResume(() => disposeTimer?.cancel());
    onDispose(() => disposeTimer?.cancel());
  }
}

/// 原songs provider：改成`List<MediaItem>`，不带封面图
/// 用于移动端
@riverpod
Future<List<MediaItem>> songs(Ref ref, String keywords) async {
  ref.cacheFor(_searchCacheTtl);
  return _searchSongMedias(
    keywords: keywords,
    withCover: false,
  );
}

/// 额外songs provider：专门提供带封面图的歌曲列表
@riverpod
Future<List<MediaItem>> songsWithCover(Ref ref, String keywords) async {
  ref.cacheFor(_searchCacheTtl);
  return _searchSongMedias(
    keywords: keywords,
    withCover: true,
  );
}

/// 专辑：转换成卡片信息(id、名称、封面、艺术家名)
@riverpod
Future<List<SearchAlbumCardData>> albums(Ref ref, String keywords) async {
  ref.cacheFor(_searchCacheTtl);

  final k = keywords.trim();
  if (k.isEmpty) return const <SearchAlbumCardData>[];

  try {
    final result = await SnowfluffMusicManager().search<Map<String, dynamic>>(
      keywords: k,
      type: SearchType.album.value,
      fromJsonT: (json) => _asMap(json),
    );

    if (result == null || result.code != 200) return const <SearchAlbumCardData>[];

    final rawResult = result.result ?? const <String, dynamic>{};
    final rawAlbums = _asList(rawResult['albums']);
    if (rawAlbums.isEmpty) return const <SearchAlbumCardData>[];

    final out = <SearchAlbumCardData>[];
    for (final raw in rawAlbums) {
      final album = _asMap(raw);
      final id = _asInt(album['id']);
      if (id <= 0) continue;

      out.add(
        SearchAlbumCardData(
          id: id,
          name: _asString(album['name']),
          coverUrl: _asString(album['picUrl']),
          artistNames: _extractAlbumArtistNames(album),
        ),
      );
    }
    return List<SearchAlbumCardData>.unmodifiable(out);
  } catch (_) {
    return const <SearchAlbumCardData>[];
  }
}

/// 艺人：转换成卡片信息(id、名称、x首歌曲·x首专辑)
@riverpod
Future<List<SearchArtistCardData>> artists(Ref ref, String keywords) async {
  ref.cacheFor(_searchCacheTtl);

  final k = keywords.trim();
  if (k.isEmpty) return const <SearchArtistCardData>[];

  try {
    final result = await SnowfluffMusicManager().searchArtist(keywords: k);
    if (result == null || result.code != 200) return const <SearchArtistCardData>[];

    final rows = result.result?.artists ?? const <SearchResultEntityArtist>[];
    if (rows.isEmpty) return const <SearchArtistCardData>[];

    return List<SearchArtistCardData>.unmodifiable(
      rows
          .where((e) => e.id > 0)
          .map(
            (e) => SearchArtistCardData(
              id: e.id,
              name: e.name,
              avatarUrl: e.picUrl,
              subtitle: '${e.musicSize}首歌曲·${e.albumSize}首专辑',
            ),
          ),
    );
  } catch (_) {
    return const <SearchArtistCardData>[];
  }
}

/// 歌单：转换成卡片信息(id、标题、封面、xx Songs)
@riverpod
Future<List<SearchPlaylistCardData>> playlists(Ref ref, String keywords) async {
  ref.cacheFor(_searchCacheTtl);

  final k = keywords.trim();
  if (k.isEmpty) return const <SearchPlaylistCardData>[];

  try {
    final result = await SnowfluffMusicManager().searchPlaylist(keywords: k);
    if (result == null || result.code != 200) return const <SearchPlaylistCardData>[];

    final rows = result.result?.playlists ?? const <SearchResultEntityPlaylist>[];
    if (rows.isEmpty) return const <SearchPlaylistCardData>[];

    return List<SearchPlaylistCardData>.unmodifiable(
      rows
          .where((e) => e.id > 0)
          .map(
            (e) => SearchPlaylistCardData(
              id: e.id,
              title: e.name,
              coverUrl: e.coverImgUrl,
              subtitle: '${e.trackCount} Songs',
            ),
          ),
    );
  } catch (_) {
    return const <SearchPlaylistCardData>[];
  }
}

Future<List<MediaItem>> _searchSongMedias({
  required String keywords,
  required bool withCover,
}) async {
  final k = keywords.trim();
  if (k.isEmpty) return const <MediaItem>[];

  try {
    final manager = SnowfluffMusicManager();

    final searchEntity = await manager.searchSong(
      keywords: k,
      limit: _searchSongLimit,
    );
    if (searchEntity == null || searchEntity.code != 200) return const <MediaItem>[];

    final songs = searchEntity.result?.songs ?? const <SearchResultEntitySong>[];
    if (songs.isEmpty) return const <MediaItem>[];

    final orderedSongs = songs.where((e) => e.id > 0).toList(growable: false);
    if (orderedSongs.isEmpty) return const <MediaItem>[];

    final idsForDetail = <int>[];
    final seen = <int>{};
    for (final s in orderedSongs) {
      if (seen.add(s.id)) idsForDetail.add(s.id);
    }

    final detail = await manager.songDetail(ids: idsForDetail);
    final songById = <int, SongDetailSongs>{
      for (final s in (detail?.songs ?? const <SongDetailSongs>[])) s.id: s,
    };
    final privilegeById = <int, SongDetailPrivileges>{
      for (final p in (detail?.privileges ?? const <SongDetailPrivileges>[])) p.id: p,
    };

    final out = <MediaItem>[];
    for (final s in orderedSongs) {
      final detailSong = songById[s.id];
      final privilege = privilegeById[s.id];

      final title = (detailSong?.name ?? '').isNotEmpty ? detailSong!.name : s.name;
      final searchArtists = s.artists.map((a) => a.name).where((e) => e.trim().isNotEmpty).join(' / ');
      final detailArtists = (detailSong?.ar ?? const <SongDetailSongsAr>[])
          .map((a) => a.name)
          .where((e) => e.trim().isNotEmpty)
          .join(' / ');
      final detailArtistIds = (detailSong?.ar ?? const <SongDetailSongsAr>[])
          .map((a) => a.id)
          .where((id) => id > 0)
          .toList(growable: false);
      final artist = searchArtists.isNotEmpty ? searchArtists : detailArtists;
      final artistIds = detailArtistIds;

      final artUri = withCover ? _buildSongArtUri(detailSong?.al?.picUrl ?? '') : null;

      out.add(
        MediaItem(
          id: s.id.toString(),
          title: title,
          artist: artist,
          duration: Duration(milliseconds: detailSong?.dt ?? 0),
          artUri: artUri,
          extras: {
            'isGrey': (privilege?.st ?? 0) < 0,
            'plLevel': privilege?.plLevel ?? '',
            'maxBrLevel': privilege?.maxBrLevel ?? '',
            'artistIds': artistIds,
          },
        ),
      );
    }

    return List<MediaItem>.unmodifiable(out);
  } catch (_) {
    return const <MediaItem>[];
  }
}

Uri? _buildSongArtUri(String picUrl) {
  final raw = picUrl.trim();
  if (raw.isEmpty) return null;
  return Uri.parse(
    'http://127.0.0.1:8848/image?url=${Uri.encodeComponent(raw)}',
  );
}

String _extractAlbumArtistNames(Map<String, dynamic> album) {
  final names = <String>[];

  for (final raw in _asList(album['artists'])) {
    final artist = _asMap(raw);
    final name = _asString(artist['name']).trim();
    if (name.isNotEmpty) names.add(name);
  }

  if (names.isEmpty) {
    final artist = _asMap(album['artist']);
    final name = _asString(artist['name']).trim();
    if (name.isNotEmpty) names.add(name);
  }

  return names.join(' / ');
}

Map<String, dynamic> _asMap(Object? json) {
  if (json is Map<String, dynamic>) return json;
  if (json is Map) {
    return json.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, dynamic>{};
}

List<dynamic> _asList(Object? value) {
  if (value is List) return value;
  return const <dynamic>[];
}

String _asString(Object? value) {
  return value?.toString() ?? '';
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
