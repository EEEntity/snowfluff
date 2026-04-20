import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:snowfluff/common/settings_service.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:path_provider/path_provider.dart';

enum CacheKind { audio, image, lyric }

class CacheStats {
  final int maxBytes;
  final int usedBytes;
  final int audioBytes;
  final int imageBytes;
  final int lyricBytes;

  const CacheStats({
    required this.maxBytes,
    required this.usedBytes,
    required this.audioBytes,
    required this.imageBytes,
    required this.lyricBytes,
  });
}

class LyricCacheData {
  final String lrc;
  final String tlyric;

  const LyricCacheData({required this.lrc, required this.tlyric});
}

class PlaylistSnapshot {
  final int playlistId;
  final String description;
  final String coverCacheKey;
  final int coverWidth;
  final int coverHeight;
  final List<int> songIds;
  final int updatedAtMs;

  const PlaylistSnapshot({
    required this.playlistId,
    required this.description,
    required this.coverCacheKey,
    required this.coverWidth,
    required this.coverHeight,
    required this.songIds,
    required this.updatedAtMs,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'playlistId': playlistId.toString(),
      'description': description,
      'coverCacheKey': coverCacheKey,
      'coverWidth': coverWidth,
      'coverHeight': coverHeight,
      'songIds': songIds
          .map((int id) => id.toString())
          .toList(growable: false),
      'updatedAtMs': updatedAtMs,
    };
  }

  static PlaylistSnapshot? fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return null;
    final dynamic rawSongIds = map['songIds'];
    final List<int> songIds = rawSongIds is List
        ? rawSongIds
              .map((dynamic e) => int.tryParse(e.toString()) ?? 0)
              .where((int e) => e > 0)
              .toList(growable: false)
        : const <int>[];
    return PlaylistSnapshot(
      playlistId: int.tryParse(map['playlistId'].toString()) ?? 0,
      description: map['description']?.toString() ?? '',
      coverCacheKey: map['coverCacheKey']?.toString() ?? '',
      coverWidth: int.tryParse(map['coverWidth'].toString()) ?? 0,
      coverHeight: int.tryParse(map['coverHeight'].toString()) ?? 0,
      songIds: songIds,
      updatedAtMs: int.tryParse(map['updatedAtMs'].toString()) ?? 0,
    );
  }
}

class _CacheEntry {
  final CacheKind kind;
  final String cacheKey;
  final String filePath;
  final int size;
  final int lastAccessMs;
  final int createdAtMs;
  final String mimeType;

  const _CacheEntry({
    required this.kind,
    required this.cacheKey,
    required this.filePath,
    required this.size,
    required this.lastAccessMs,
    required this.createdAtMs,
    required this.mimeType,
  });

  String get storageKey => '${kind.name}:$cacheKey';

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'kind': kind.name,
      'cacheKey': cacheKey,
      'filePath': filePath,
      'size': size,
      'lastAccessMs': lastAccessMs,
      'createdAtMs': createdAtMs,
      'mimeType': mimeType,
    };
  }

  static _CacheEntry? fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return null;
    final String kindName = map['kind']?.toString() ?? '';
    CacheKind? kind;
    for (final CacheKind value in CacheKind.values) {
      if (value.name == kindName) {
        kind = value;
        break;
      }
    }
    if (kind == null) return null;
    final String cacheKey = map['cacheKey']?.toString() ?? '';
    final String filePath = map['filePath']?.toString() ?? '';
    final int size = int.tryParse(map['size'].toString()) ?? 0;
    final int lastAccessMs = int.tryParse(map['lastAccessMs'].toString()) ?? 0;
    final int createdAtMs = int.tryParse(map['createdAtMs'].toString()) ?? 0;
    final String mimeType = map['mimeType']?.toString() ?? '';
    if (cacheKey.isEmpty || filePath.isEmpty || size <= 0) return null;
    return _CacheEntry(
      kind: kind,
      cacheKey: cacheKey,
      filePath: filePath,
      size: size,
      lastAccessMs: lastAccessMs,
      createdAtMs: createdAtMs,
      mimeType: mimeType,
    );
  }
}

class MediaCacheService {
  MediaCacheService._internal();

  static final MediaCacheService _instance = MediaCacheService._internal();

  factory MediaCacheService() => _instance;

  static const String _indexBoxName = 'media_cache_index_v1';
  static const String _playlistBoxName = 'media_playlist_snapshot_v1';
  static const int _touchWriteIntervalMs = 30000;

  final Map<String, int> _lastTouchWriteMs = <String, int>{};

  bool _inited = false;
  Box<Map<dynamic, dynamic>>? _indexBox;
  Box<Map<dynamic, dynamic>>? _playlistBox;
  late Directory _rootDir;
  late Directory _audioDir;
  late Directory _imageDir;
  late Directory _lyricDir;

  Future<void> init() async {
    if (_inited) return;
    final Directory base = await getApplicationCacheDirectory();
    _rootDir = Directory('${base.path}/media_cache');
    _audioDir = Directory('${_rootDir.path}/audio');
    _imageDir = Directory('${_rootDir.path}/image');
    _lyricDir = Directory('${_rootDir.path}/lyric');
    await _audioDir.create(recursive: true);
    await _imageDir.create(recursive: true);
    await _lyricDir.create(recursive: true);

    _indexBox = await Hive.openBox<Map<dynamic, dynamic>>(_indexBoxName);
    _playlistBox = await Hive.openBox<Map<dynamic, dynamic>>(_playlistBoxName);
    _inited = true;

    unawaited(pruneIfNeeded());
  }

  Future<File?> getCachedFile(
    CacheKind kind,
    String cacheKey, {
    bool touch = true,
  }) async {
    await init();
    final String storageKey = _storageKey(kind, cacheKey);
    final _CacheEntry? entry = _entryFromStorageKey(storageKey);
    if (entry == null) return null;
    final File file = File(entry.filePath);
    if (!await file.exists()) {
      await _indexBox!.delete(storageKey);
      return null;
    }
    if (touch) {
      await _touchEntry(entry);
    }
    return file;
  }

  Future<String> buildPathForKey(
    CacheKind kind,
    String cacheKey, {
    required String extension,
  }) async {
    await init();
    final Directory parent = await _shardedDir(kind, cacheKey);
    final String safeName = _safeFileName(cacheKey);
    final String ext = extension.isEmpty ? 'bin' : extension.toLowerCase();
    return '${parent.path}/$safeName.$ext';
  }

  Future<void> registerFile({
    required CacheKind kind,
    required String cacheKey,
    required String filePath,
    required int size,
    String mimeType = '',
  }) async {
    if (size <= 0 || filePath.isEmpty) return;
    await init();
    if (!SettingsService.cacheEnabled) return;

    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final _CacheEntry entry = _CacheEntry(
      kind: kind,
      cacheKey: cacheKey,
      filePath: filePath,
      size: size,
      lastAccessMs: nowMs,
      createdAtMs: nowMs,
      mimeType: mimeType,
    );
    await _indexBox!.put(entry.storageKey, entry.toMap());
    await pruneIfNeeded();
  }

  Future<void> removeByKey(CacheKind kind, String cacheKey) async {
    await init();
    final String storageKey = _storageKey(kind, cacheKey);
    final _CacheEntry? entry = _entryFromStorageKey(storageKey);
    if (entry != null) {
      final File file = File(entry.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    await _indexBox!.delete(storageKey);
  }

  Future<void> clearAll() async {
    await init();
    await _indexBox!.clear();
    await _playlistBox!.clear();
    if (await _rootDir.exists()) {
      await _rootDir.delete(recursive: true);
    }
    await _audioDir.create(recursive: true);
    await _imageDir.create(recursive: true);
    await _lyricDir.create(recursive: true);
  }

  Future<CacheStats> getStats() async {
    await init();
    final List<_CacheEntry> entries = await _loadValidEntriesAndCleanup();
    int audioBytes = 0;
    int imageBytes = 0;
    int lyricBytes = 0;
    for (final _CacheEntry entry in entries) {
      switch (entry.kind) {
        case CacheKind.audio:
          audioBytes += entry.size;
          break;
        case CacheKind.image:
          imageBytes += entry.size;
          break;
        case CacheKind.lyric:
          lyricBytes += entry.size;
          break;
      }
    }
    final int usedBytes = audioBytes + imageBytes + lyricBytes;
    return CacheStats(
      maxBytes: SettingsService.cacheMaxBytes,
      usedBytes: usedBytes,
      audioBytes: audioBytes,
      imageBytes: imageBytes,
      lyricBytes: lyricBytes,
    );
  }

  Future<void> pruneIfNeeded() async {
    await init();
    final List<_CacheEntry> allEntries = await _loadValidEntriesAndCleanup();
    if (allEntries.isEmpty) return;

    final int totalLimit = SettingsService.cacheMaxBytes;
    final int reclaimTarget = (totalLimit * 0.95).floor();

    final int audioRatio = SettingsService.cacheAudioPercent;
    final int imageRatio = SettingsService.cacheImagePercent;
    final int lyricRatio = SettingsService.cacheLyricPercent;
    int ratioSum = audioRatio + imageRatio + lyricRatio;
    if (ratioSum <= 0) ratioSum = 100;

    final Map<CacheKind, int> kindLimit = <CacheKind, int>{
      CacheKind.audio: (totalLimit * audioRatio / ratioSum).floor(),
      CacheKind.image: (totalLimit * imageRatio / ratioSum).floor(),
      CacheKind.lyric: (totalLimit * lyricRatio / ratioSum).floor(),
    };

    final Map<CacheKind, List<_CacheEntry>> grouped =
        <CacheKind, List<_CacheEntry>>{
          CacheKind.audio: <_CacheEntry>[],
          CacheKind.image: <_CacheEntry>[],
          CacheKind.lyric: <_CacheEntry>[],
        };
    for (final _CacheEntry entry in allEntries) {
      grouped[entry.kind]!.add(entry);
    }

    for (final CacheKind kind in CacheKind.values) {
      grouped[kind]!.sort((a, b) => a.lastAccessMs.compareTo(b.lastAccessMs));
      int used = grouped[kind]!.fold(
        0,
        (int sum, _CacheEntry e) => sum + e.size,
      );
      final int limit = kindLimit[kind] ?? 0;
      while (limit > 0 && used > limit && grouped[kind]!.isNotEmpty) {
        final _CacheEntry victim = grouped[kind]!.removeAt(0);
        await _deleteEntry(victim);
        used -= victim.size;
      }
    }

    final List<_CacheEntry> remaining = await _loadValidEntriesAndCleanup();
    int totalUsed = remaining.fold(0, (int sum, _CacheEntry e) => sum + e.size);
    if (totalUsed <= totalLimit) return;

    remaining.sort((a, b) => a.lastAccessMs.compareTo(b.lastAccessMs));
    for (final _CacheEntry victim in remaining) {
      if (totalUsed <= reclaimTarget) break;
      await _deleteEntry(victim);
      totalUsed -= victim.size;
    }
  }

  Future<LyricCacheData?> readLyric(int songId) async {
    if (songId <= 0) return null;
    final String lrcKey = _lyricMainKey(songId);
    final String tlrcKey = _lyricTransKey(songId);
    final List<File?> files = await Future.wait<File?>([
      getCachedFile(CacheKind.lyric, lrcKey, touch: false),
      getCachedFile(CacheKind.lyric, tlrcKey, touch: false),
    ]);
    final File? lrcFile = files[0];
    if (lrcFile == null) return null;
    final File? tlyricFile = files[1];
    final List<String> contents = await Future.wait<String>([
      lrcFile.readAsString(),
      tlyricFile?.readAsString() ?? Future.value(''),
    ]);
    final String lrc = contents[0];
    final String tlyric = contents[1];
    return LyricCacheData(lrc: lrc, tlyric: tlyric);
  }

  Future<void> writeLyric(
    int songId, {
    required String lrc,
    String tlyric = '',
  }) async {
    if (songId <= 0 || lrc.isEmpty) return;
    await init();
    if (!SettingsService.cacheEnabled) return;

    final String lrcKey = _lyricMainKey(songId);
    final String lrcPath = await buildPathForKey(
      CacheKind.lyric,
      lrcKey,
      extension: 'lrc',
    );
    await _writeTextAtomically(lrcPath, lrc);
    final File lrcFile = File(lrcPath);
    await registerFile(
      kind: CacheKind.lyric,
      cacheKey: lrcKey,
      filePath: lrcPath,
      size: await lrcFile.length(),
      mimeType: 'text/plain',
    );

    final String tlrcKey = _lyricTransKey(songId);
    if (tlyric.isNotEmpty) {
      final String tlyricPath = await buildPathForKey(
        CacheKind.lyric,
        tlrcKey,
        extension: 'lrc',
      );
      await _writeTextAtomically(tlyricPath, tlyric);
      final File tlyricFile = File(tlyricPath);
      await registerFile(
        kind: CacheKind.lyric,
        cacheKey: tlrcKey,
        filePath: tlyricPath,
        size: await tlyricFile.length(),
        mimeType: 'text/plain',
      );
    } else {
      await removeByKey(CacheKind.lyric, tlrcKey);
    }
  }

  Future<void> savePlaylistSnapshot(PlaylistSnapshot snapshot) async {
    await init();
    await _playlistBox!.put(
      'playlist:${snapshot.playlistId}',
      snapshot.toMap(),
    );
  }

  Future<PlaylistSnapshot?> loadPlaylistSnapshot(int playlistId) async {
    await init();
    final Map<dynamic, dynamic>? raw = _playlistBox!.get(
      'playlist:$playlistId',
    );
    return PlaylistSnapshot.fromMap(raw);
  }

  Future<void> removePlaylistSnapshot(int playlistId) async {
    await init();
    await _playlistBox!.delete('playlist:$playlistId');
  }

  Future<void> saveLibraryPlaylists({
    required int uid,
    required List<Map<String, dynamic>> playlists,
    required int updatedAtMs,
  }) async {
    if (uid <= 0) return;
    await init();
    await _playlistBox!.put('library:list:$uid', <String, dynamic>{
      'uid': uid.toString(),
      'updatedAtMs': updatedAtMs,
      'playlists': playlists,
    });
  }

  Future<List<Map<dynamic, dynamic>>> loadLibraryPlaylists(int uid) async {
    if (uid <= 0) return const <Map<dynamic, dynamic>>[];
    await init();
    final Map<dynamic, dynamic>? raw = _playlistBox!.get('library:list:$uid');
    if (raw == null) return const <Map<dynamic, dynamic>>[];
    final dynamic list = raw['playlists'];
    if (list is! List) return const <Map<dynamic, dynamic>>[];
    final List<Map<dynamic, dynamic>> out = <Map<dynamic, dynamic>>[];
    for (final dynamic item in list) {
      if (item is Map) {
        out.add(item.map((dynamic k, dynamic v) => MapEntry(k, v)));
      }
    }
    return out;
  }

  Future<bool> isLibraryPlaylistId(int playlistId) async {
    if (playlistId <= 0) return false;
    await init();
    for (final String key in _playlistBox!.keys.whereType<String>()) {
      if (!key.startsWith('library:list:')) continue;
      final Map<dynamic, dynamic>? raw = _playlistBox!.get(key);
      final dynamic list = raw?['playlists'];
      if (list is! List) continue;
      for (final dynamic item in list) {
        if (item is! Map) continue;
        final int id = int.tryParse(item['id'].toString()) ?? 0;
        if (id == playlistId) return true;
      }
    }
    return false;
  }

  Future<bool> isLikedPlaylistId(int playlistId) async {
    if (playlistId <= 0) return false;
    await init();
    for (final String key in _playlistBox!.keys.whereType<String>()) {
      if (!key.startsWith('library:list:')) continue;
      final Map<dynamic, dynamic>? raw = _playlistBox!.get(key);
      final dynamic list = raw?['playlists'];
      if (list is! List) continue;
      for (final dynamic item in list) {
        if (item is! Map) continue;
        final int id = int.tryParse(item['id'].toString()) ?? 0;
        if (id != playlistId) continue;
        final int specialType =
            int.tryParse(item['specialType'].toString()) ?? 0;
        final bool likedByType = specialType == 5;
        final bool likedByName = (item['name']?.toString() ?? '').contains(
          '喜欢',
        );
        return likedByType || likedByName;
      }
    }
    return false;
  }

  Future<void> saveLikedPreviewSongs({
    required int playlistId,
    required List<Map<String, dynamic>> songs,
    required int updatedAtMs,
  }) async {
    if (playlistId <= 0) return;
    await init();
    await _playlistBox!.put('liked:preview:$playlistId', <String, dynamic>{
      'playlistId': playlistId.toString(),
      'updatedAtMs': updatedAtMs,
      'songs': songs,
    });
  }

  Future<List<Map<dynamic, dynamic>>> loadLikedPreviewSongs(
    int playlistId,
  ) async {
    if (playlistId <= 0) return const <Map<dynamic, dynamic>>[];
    await init();
    final Map<dynamic, dynamic>? raw = _playlistBox!.get(
      'liked:preview:$playlistId',
    );
    if (raw == null) return const <Map<dynamic, dynamic>>[];
    final dynamic list = raw['songs'];
    if (list is! List) return const <Map<dynamic, dynamic>>[];
    final List<Map<dynamic, dynamic>> out = <Map<dynamic, dynamic>>[];
    for (final dynamic item in list) {
      if (item is Map) {
        out.add(item.map((dynamic k, dynamic v) => MapEntry(k, v)));
      }
    }
    return out;
  }

  Future<void> saveDailyRecommendSongs({
    required String dateKey,
    required List<Map<String, dynamic>> songs,
    required int updatedAtMs,
  }) async {
    if (dateKey.isEmpty) return;
    await init();
    await _playlistBox!.put('daily:recommend:$dateKey', <String, dynamic>{
      'dateKey': dateKey,
      'updatedAtMs': updatedAtMs,
      'songs': songs,
    });

    final List<String> obsoleteKeys = <String>[];
    for (final String key in _playlistBox!.keys.whereType<String>()) {
      if (!key.startsWith('daily:recommend:')) continue;
      if (key == 'daily:recommend:$dateKey') continue;
      obsoleteKeys.add(key);
    }
    if (obsoleteKeys.isNotEmpty) {
      await _playlistBox!.deleteAll(obsoleteKeys);
    }
  }

  Future<void> saveDiscoverRecommendPlaylists({
    required List<Map<String, dynamic>> playlists,
    required int updatedAtMs,
  }) async {
    await init();
    await _playlistBox!.put('discover:recommend:playlists', <String, dynamic>{
      'updatedAtMs': updatedAtMs,
      'playlists': playlists,
    });
  }

  Future<int?> loadDiscoverRecommendPlaylistsUpdatedAtMs() async {
    await init();
    final Map<dynamic, dynamic>? raw = _playlistBox!.get(
      'discover:recommend:playlists',
    );
    if (raw == null) return null;
    final int value = int.tryParse(raw['updatedAtMs'].toString()) ?? 0;
    return value > 0 ? value : null;
  }

  Future<List<Map<dynamic, dynamic>>> loadDiscoverRecommendPlaylists() async {
    await init();
    final Map<dynamic, dynamic>? raw = _playlistBox!.get(
      'discover:recommend:playlists',
    );
    if (raw == null) return const <Map<dynamic, dynamic>>[];
    final dynamic list = raw['playlists'];
    if (list is! List) return const <Map<dynamic, dynamic>>[];
    final List<Map<dynamic, dynamic>> out = <Map<dynamic, dynamic>>[];
    for (final dynamic item in list) {
      if (item is Map) {
        out.add(item.map((dynamic k, dynamic v) => MapEntry(k, v)));
      }
    }
    return out;
  }

  Future<List<Map<dynamic, dynamic>>> loadDailyRecommendSongs(
    String dateKey,
  ) async {
    if (dateKey.isEmpty) return const <Map<dynamic, dynamic>>[];
    await init();
    final Map<dynamic, dynamic>? raw = _playlistBox!.get(
      'daily:recommend:$dateKey',
    );
    if (raw == null) return const <Map<dynamic, dynamic>>[];
    final dynamic songs = raw['songs'];
    if (songs is! List) return const <Map<dynamic, dynamic>>[];
    final List<Map<dynamic, dynamic>> out = <Map<dynamic, dynamic>>[];
    for (final dynamic item in songs) {
      if (item is Map) {
        out.add(item.map((dynamic k, dynamic v) => MapEntry(k, v)));
      }
    }
    return out;
  }

  Future<int?> loadDailyRecommendSongsUpdatedAtMs(String dateKey) async {
    if (dateKey.isEmpty) return null;
    await init();
    final Map<dynamic, dynamic>? raw = _playlistBox!.get(
      'daily:recommend:$dateKey',
    );
    if (raw == null) return null;
    final int value = int.tryParse(raw['updatedAtMs'].toString()) ?? 0;
    return value > 0 ? value : null;
  }

  Future<void> _touchEntry(_CacheEntry entry) async {
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final int lastMs = _lastTouchWriteMs[entry.storageKey] ?? 0;
    if (nowMs - lastMs < _touchWriteIntervalMs) return;
    _lastTouchWriteMs[entry.storageKey] = nowMs;
    await _indexBox!.put(
      entry.storageKey,
      entry.copyWith(lastAccessMs: nowMs).toMap(),
    );
  }

  Future<void> _writeTextAtomically(String filePath, String content) async {
    final File target = File(filePath);
    await target.parent.create(recursive: true);
    final File tmp = File(
      '$filePath.tmp_${DateTime.now().microsecondsSinceEpoch}',
    );
    await tmp.writeAsString(content, flush: true);
    if (await target.exists()) {
      await target.delete();
    }
    await tmp.rename(filePath);
  }

  Future<List<_CacheEntry>> _loadValidEntriesAndCleanup() async {
    final List<_CacheEntry> entries = <_CacheEntry>[];
    final List<String> staleKeys = <String>[];
    for (final String storageKey in _indexBox!.keys.cast<String>()) {
      final Map<dynamic, dynamic>? raw = _indexBox!.get(storageKey);
      final _CacheEntry? entry = _CacheEntry.fromMap(raw);
      if (entry == null) {
        staleKeys.add(storageKey);
        continue;
      }
      final File file = File(entry.filePath);
      if (!await file.exists()) {
        staleKeys.add(storageKey);
        continue;
      }
      final int length = await file.length();
      if (length <= 0) {
        staleKeys.add(storageKey);
        continue;
      }
      if (length != entry.size) {
        final _CacheEntry fixed = entry.copyWith(size: length);
        await _indexBox!.put(storageKey, fixed.toMap());
        entries.add(fixed);
      } else {
        entries.add(entry);
      }
    }
    if (staleKeys.isNotEmpty) {
      await _indexBox!.deleteAll(staleKeys);
    }
    return entries;
  }

  Future<void> _deleteEntry(_CacheEntry entry) async {
    final File file = File(entry.filePath);
    if (await file.exists()) {
      await file.delete();
    }
    await _indexBox!.delete(entry.storageKey);
  }

  _CacheEntry? _entryFromStorageKey(String storageKey) {
    final Map<dynamic, dynamic>? raw = _indexBox!.get(storageKey);
    return _CacheEntry.fromMap(raw);
  }

  Future<Directory> _shardedDir(CacheKind kind, String cacheKey) async {
    final Directory kindDir = _kindDir(kind);
    final String hash = hash64(cacheKey);
    final Directory shard = Directory(
      '${kindDir.path}/${hash.substring(0, 2)}/${hash.substring(2, 4)}',
    );
    await shard.create(recursive: true);
    return shard;
  }

  Directory _kindDir(CacheKind kind) {
    switch (kind) {
      case CacheKind.audio:
        return _audioDir;
      case CacheKind.image:
        return _imageDir;
      case CacheKind.lyric:
        return _lyricDir;
    }
  }

  String _storageKey(CacheKind kind, String cacheKey) {
    return '${kind.name}:$cacheKey';
  }

  String _lyricMainKey(int songId) => 'song_${songId}_main';

  String _lyricTransKey(int songId) => 'song_${songId}_trans';

  static String hash64(String input) {
    const int fnvOffset = 0xcbf29ce484222325;
    const int fnvPrime = 0x100000001b3;
    int hash = fnvOffset;
    for (final int b in utf8.encode(input)) {
      hash ^= b;
      hash = (hash * fnvPrime) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  static String safeImageIdentityFromUrl(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return hash64(url);

    final RegExp idReg = RegExp(
      r'/([0-9]{6,})\.(jpg|jpeg|png|webp|gif)$',
      caseSensitive: false,
    );
    final Match? m = idReg.firstMatch(uri.path);
    if (m != null) {
      return m.group(1)!;
    }

    final String? idFromPath = _lastNumericSegment(uri.path);
    if (idFromPath != null && idFromPath.length >= 6) {
      return idFromPath;
    }
    return hash64(url);
  }

  static String? _lastNumericSegment(String path) {
    final List<String> segments = path
        .split('/')
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);
    for (int i = segments.length - 1; i >= 0; i--) {
      final String seg = segments[i].split('.').first;
      if (RegExp(r'^[0-9]+$').hasMatch(seg)) {
        return seg;
      }
    }
    return null;
  }

  static String makeImageCacheKey({
    required String identity,
    required int width,
    required int height,
    String variant = 'default',
  }) {
    final int w = width > 0 ? width : 0;
    final int h = height > 0 ? height : 0;
    return 'img_${identity}_${variant}_${w}x$h';
  }

  static String _safeFileName(String input) {
    final String normalized = input
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (normalized.isEmpty) return 'cache_file';
    if (normalized.length <= 64) return normalized;
    return normalized.substring(0, 64);
  }
}

extension on _CacheEntry {
  _CacheEntry copyWith({
    CacheKind? kind,
    String? cacheKey,
    String? filePath,
    int? size,
    int? lastAccessMs,
    int? createdAtMs,
    String? mimeType,
  }) {
    return _CacheEntry(
      kind: kind ?? this.kind,
      cacheKey: cacheKey ?? this.cacheKey,
      filePath: filePath ?? this.filePath,
      size: size ?? this.size,
      lastAccessMs: lastAccessMs ?? this.lastAccessMs,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      mimeType: mimeType ?? this.mimeType,
    );
  }
}
