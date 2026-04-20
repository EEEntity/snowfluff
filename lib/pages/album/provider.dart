import 'package:audio_service/audio_service.dart';
import 'package:ncm_api/api/agent.dart';
import 'package:ncm_api/api/album.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'provider.g.dart';

const int _albumDetailMaxAttempts = 3;
const AlbumData _emptyAlbumData = AlbumData(
  name: '',
  description: '',
  coverUrl: '',
  artists: <String>[],
  medias: <MediaItem>[],
  publishTime: 0,
  size: 0,
);

class AlbumData {
  final String name; // 专辑名称
  final String description; // 专辑描述
  final String coverUrl; // 专辑封面URL
  final List<String> artists; // 专辑艺术家列表
  // 后续带上艺人id，方便点击跳转
  final List<MediaItem> medias; // 专辑中的媒体项列表
  final int publishTime; // 专辑发布时间
  final int size; // 专辑包含的歌曲数量

  const AlbumData({
    required this.name,
    required this.description,
    required this.coverUrl,
    required this.artists,
    required this.medias,
    required this.publishTime,
    required this.size,
  });
}

@riverpod
Future<AlbumData> albumDetail(Ref ref, int id) async {
  if (id <= 0) {
    return _emptyAlbumData;
  }
  final manager = SnowfluffMusicManager();

  for (int attempt = 1; attempt <= _albumDetailMaxAttempts; attempt++) {
    try {
      // 并发请求
      final results = await Future.wait([
        manager.albumInfo(id: id),
        manager.albumInfoV1(id: id),
      ]);
      final detail = results[0] as AlbumInfoEntity?;
      final detailV1 = results[1] as AlbumInfoEntityV1?;
      final album = detail?.album;
      if (album != null) {
        final description = detailV1?.album?.description ?? '';
        final artists = _buildArtistNames(album);
        final privilegeBySongId = _buildPrivilegeMap(detailV1?.songs ?? const <AlbumInfoSongs>[]);
        final medias = _buildAlbumMedias(
          songs: album.songs,
          albumCoverUrl: album.picUrl,
          privilegeBySongId: privilegeBySongId,
        );
        return AlbumData(
          name: album.name,
          description: description,
          coverUrl: album.picUrl,
          artists: artists,
          medias: medias,
          publishTime: album.publishTime,
          size: album.size > 0 ? album.size : medias.length,
        );
      }
    } catch (_) {
      // ignore and retry
    }

    if (attempt < _albumDetailMaxAttempts) {
      await Future.delayed(Duration(milliseconds: 200 * attempt));
    }
  }
  return _emptyAlbumData;
}

List<String> _buildArtistNames(AlbumInfoAlbum album) {
  final names = <String>[];
  for (final a in album.artists) {
    if (a.name.isNotEmpty) names.add(a.name);
  }
  // artists为空时回退到artist字段
  if (names.isEmpty) {
    final fallback = album.artist?.name ?? '';
    if (fallback.isNotEmpty) {
      names.add(fallback);
    }
  }
  return List<String>.unmodifiable(names);
}

Map<int, AlbumInfoSongsPrivilege> _buildPrivilegeMap(List<AlbumInfoSongs> songs) {
  final map = <int, AlbumInfoSongsPrivilege>{};
  for (final s in songs) {
    final p = s.privilege;
    if (p != null) {
      map[s.id] = p;
    }
  }
  return map;
}

List<MediaItem> _buildAlbumMedias({
  required List<AlbumInfoAlbumSongs> songs,
  required String albumCoverUrl,
  required Map<int, AlbumInfoSongsPrivilege> privilegeBySongId,
}) {
  final artUri = Uri.parse(
    'http://127.0.0.1:8848/image?url=${Uri.encodeComponent(albumCoverUrl)}',
  );

  if (songs.isEmpty) return const <MediaItem>[];

  String prevDiscKey = '';
  int segmentedNo = 0;

  return List<MediaItem>.generate(
    songs.length,
    (i) {
      final s = songs[i];
      final privilege = privilegeBySongId[s.id];

      final discKey = s.disc.trim();
      if (i == 0 || discKey != prevDiscKey) {
        segmentedNo = 1;
      } else {
        segmentedNo++;
      }
      prevDiscKey = discKey;

      return MediaItem(
        id: s.id.toString(),
        title: s.name,
        duration: Duration(milliseconds: s.duration),
        artist: s.artists.map((a) => a.name).join(' / '),
        artUri: artUri,
        extras: {
          'isGrey': (privilege?.st ?? 0) < 0,
          'plLevel': privilege?.plLevel ?? '',
          'maxBrLevel': privilege?.maxBrLevel ?? '',
          'disc': s.disc,
          'no': segmentedNo,
          'artistIds': s.artists.map((a) => a.id).toList(growable: false),
        },
      );
    },
    growable: false,
  );
}
