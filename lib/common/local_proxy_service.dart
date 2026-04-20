import 'dart:async';
import 'dart:io';
import 'package:snowfluff/common/media_cache_service.dart';
import 'package:snowfluff/common/settings_service.dart';
import 'package:ncm_api/api/agent.dart';
import 'package:ncm_api/api/song.dart';

// url缓存
class _CachedUrl {
  final String url; // url
  final DateTime expireTime; // 过期时间
  _CachedUrl(this.url, this.expireTime);
}

// 歌曲音质枚举
enum SongUrlLevel {
  standard, // 标准
  // higher, // 较高
  exhigh, // 极高
  lossless, // 无损
  hires, // Hi-Res
  jyeffect, // 高清环绕声
  sky, // 沉浸环绕声
  // dolby, // 杜比全景声
  jymaster, // 超清母带
}
enum SongUrlEncodeType {
  mp3,
  aac,
  flac,
}

// 歌曲音质缓存key
class _SongUrlKey {
  final String songId;
  final SongUrlLevel level;
  final SongUrlEncodeType encodeType;
  const _SongUrlKey({
    required this.songId,
    required this.level,
    required this.encodeType,
  });
  @override
  bool operator ==(Object other) {
    return other is _SongUrlKey &&
        other.songId == songId &&
        other.level == level &&
        other.encodeType == encodeType;
  }
  @override
  int get hashCode => Object.hash(songId, level, encodeType);
}

class LocalProxyService {
  LocalProxyService._internal();
  static final LocalProxyService _instance = LocalProxyService._internal();
  factory LocalProxyService() => _instance;
  final int port = 8848;
  final MediaCacheService _cacheService = MediaCacheService();
  final Map<_SongUrlKey, _CachedUrl> _cache = <_SongUrlKey, _CachedUrl>{};
  final Map<_SongUrlKey, DateTime> _lastRequestTime = <_SongUrlKey, DateTime>{};
  final Map<_SongUrlKey, Future<String>> _inflightUrlRequests = <_SongUrlKey, Future<String>>{};
  final Map<String, Future<void>> _audioDownloadTasks = <String, Future<void>>{};
  final Map<String, Future<void>> _imageDownloadTasks = <String, Future<void>>{};

  HttpServer? _server;
  bool _started = false;
  // 设置connectionTimeout避免网络很差时无限期挂起线程
  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..idleTimeout = const Duration(seconds: 15);

  final Duration minInterval = const Duration(seconds: 1); // 最小请求间隔

  Future<void> start() async {
    if (_started) return;
    await _cacheService.init();
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _started = true;

    _server!.listen((HttpRequest request) async {
      final String path = request.uri.path;
      if (path.startsWith('/song/')) {
        await _handleSongRequest(request);
        return;
      }
      if (path == '/image') {
        await _handleImageRequest(request);
        return;
      }
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not found');
      await request.response.close();
    });
  }

  Future<void> _handleSongRequest(HttpRequest request) async {
    final String songId = request.uri.pathSegments.isNotEmpty
        ? request.uri.pathSegments.last
        : '';
    if (songId.isEmpty) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Missing song id');
      await request.response.close();
      return;
    }

    final SongUrlLevel level = SettingsService.musicQuality;
    final SongUrlEncodeType encodeType = SongUrlEncodeType.values.firstWhere(
      (SongUrlEncodeType e) => e.name == request.uri.queryParameters['encodeType'],
      orElse: () => SongUrlEncodeType.flac,
    );

    final String audioCacheKey = _audioCacheKey(songId, level, encodeType);

    try {
      final File? cached = await _findBestCachedAudio(songId, level, encodeType);
      if (cached != null) {
        await _serveLocalFile(
          request,
          cached,
          mimeType: _audioMimeFromExt(_extensionFromPath(cached.path, fallback: 'flac')),
          supportsRange: true,
        );
        return;
      }

      final String realUrl = await _getUrl(
        songId,
        level: level,
        encodeType: encodeType,
      );
      if (realUrl.isEmpty) {
        throw StateError('Empty song url');
      }

      final HttpClientRequest realRequest = await _httpClient.getUrl(Uri.parse(realUrl));
      final String? range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null && range.isNotEmpty) {
        realRequest.headers.set(HttpHeaders.rangeHeader, range);
      }
      final HttpClientResponse realResponse = await realRequest.close();
      _forwardHeaders(realResponse.headers, request.response.headers);
      request.response.statusCode = realResponse.statusCode;

      final bool canInlineCache =
          SettingsService.cacheEnabled &&
          range == null &&
          realResponse.statusCode == HttpStatus.ok;

      File? tmpFile;
      IOSink? sink;
      String? finalPath;
      final String ext = _extensionFromUrl(realUrl, fallback: encodeType.name);

      if (canInlineCache) {
        finalPath = await _cacheService.buildPathForKey(
          CacheKind.audio,
          audioCacheKey,
          extension: ext,
        );
        tmpFile = File('$finalPath.part_${DateTime.now().microsecondsSinceEpoch}');
        await tmpFile.parent.create(recursive: true);
        sink = tmpFile.openWrite();
      } else if (SettingsService.cacheEnabled) {
        unawaited(_downloadAudioInBackground(
          cacheKey: audioCacheKey,
          realUrl: realUrl,
          ext: ext,
          mimeType: _audioMimeFromExt(ext),
        ));
      }

      try {
        await for (final List<int> chunk in realResponse) {
          request.response.add(chunk);
          sink?.add(chunk);
        }
        await sink?.flush();
        await sink?.close();
        await request.response.close();

        if (tmpFile != null && finalPath != null && await tmpFile.exists()) {
          final int size = await tmpFile.length();
          if (size > 0) {
            final File finalFile = File(finalPath);
            if (await finalFile.exists()) {
              await finalFile.delete();
            }
            await tmpFile.rename(finalPath);
            await _cacheService.registerFile(
              kind: CacheKind.audio,
              cacheKey: audioCacheKey,
              filePath: finalPath,
              size: size,
              mimeType: _audioMimeFromExt(ext),
            );
          } else {
            await tmpFile.delete();
          }
        }
      } catch (_) {
        await sink?.close();
        if (tmpFile != null && await tmpFile.exists()) {
          await tmpFile.delete();
        }
        rethrow;
      }
    } catch (e) {
      try {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write('Proxy error: $e');
        await request.response.close();
      } catch (_) {
        // 响应头已发送（客户端在流式传输中途断开），无法再写入错误响应
      }
    }
  }

  Future<void> _handleImageRequest(HttpRequest request) async {
    final String raw = request.uri.queryParameters['url'] ?? '';
    if (raw.isEmpty) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Missing url');
      await request.response.close();
      return;
    }

    final String realUrl = Uri.decodeComponent(raw);
    final int width = _resolveImageWidth(realUrl, request.uri);
    final int height = _resolveImageHeight(realUrl, request.uri);
    final String pid = request.uri.queryParameters['pid']?.trim() ?? '';
    final String identity = pid.isNotEmpty
        ? pid
        : MediaCacheService.safeImageIdentityFromUrl(realUrl);
    final String imageCacheKey = MediaCacheService.makeImageCacheKey(
      identity: identity,
      width: width,
      height: height,
    );

    try {
      final File? cached = await _cacheService.getCachedFile(
        CacheKind.image,
        imageCacheKey,
      );
      if (cached != null) {
        await _serveLocalFile(
          request,
          cached,
          mimeType: _imageMimeFromExt(_extensionFromPath(cached.path, fallback: 'jpg')),
          supportsRange: false,
        );
        return;
      }

      final HttpClientRequest realRequest = await _httpClient.getUrl(Uri.parse(realUrl));
      realRequest.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/42.0.2311.135 Safari/537.36 Edge/13.10586',
      );
      realRequest.headers.set(HttpHeaders.refererHeader, 'http://music.163.com/');

      final HttpClientResponse realResponse = await realRequest.close();
      _forwardHeaders(realResponse.headers, request.response.headers);
      request.response.statusCode = realResponse.statusCode;

      final String ext = _extensionFromUrl(realUrl, fallback: 'jpg');
      final bool canCache = SettingsService.cacheEnabled && realResponse.statusCode == HttpStatus.ok;
      File? tmpFile;
      IOSink? sink;
      String? finalPath;

      if (canCache) {
        finalPath = await _cacheService.buildPathForKey(
          CacheKind.image,
          imageCacheKey,
          extension: ext,
        );
        tmpFile = File('$finalPath.part_${DateTime.now().microsecondsSinceEpoch}');
        await tmpFile.parent.create(recursive: true);
        sink = tmpFile.openWrite();
      } else if (SettingsService.cacheEnabled) {
        unawaited(_downloadImageInBackground(
          cacheKey: imageCacheKey,
          realUrl: realUrl,
          ext: ext,
          mimeType: _imageMimeFromExt(ext),
        ));
      }

      try {
        await for (final List<int> chunk in realResponse) {
          request.response.add(chunk);
          sink?.add(chunk);
        }
        await sink?.flush();
        await sink?.close();
        await request.response.close();

        if (tmpFile != null && finalPath != null && await tmpFile.exists()) {
          final int size = await tmpFile.length();
          if (size > 0) {
            final File finalFile = File(finalPath);
            if (await finalFile.exists()) {
              await finalFile.delete();
            }
            await tmpFile.rename(finalPath);
            await _cacheService.registerFile(
              kind: CacheKind.image,
              cacheKey: imageCacheKey,
              filePath: finalPath,
              size: size,
              mimeType: _imageMimeFromExt(ext),
            );
          } else {
            await tmpFile.delete();
          }
        }
      } catch (_) {
        await sink?.close();
        if (tmpFile != null && await tmpFile.exists()) {
          await tmpFile.delete();
        }
        rethrow;
      }
    } catch (e) {
      try {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write('Proxy image error: $e');
        await request.response.close();
      } catch (_) {
        // 响应头已发送（客户端在流式传输中途断开），无法再写入错误响应
      }
    }
  }

  Future<void> _downloadAudioInBackground({
    required String cacheKey,
    required String realUrl,
    required String ext,
    required String mimeType,
  }) async {
    final Future<void>? existing = _audioDownloadTasks[cacheKey];
    if (existing != null) return;

    final Future<void> task = () async {
      final File? already = await _cacheService.getCachedFile(CacheKind.audio, cacheKey, touch: false);
      if (already != null) return;

      final HttpClientRequest req = await _httpClient.getUrl(Uri.parse(realUrl));
      final HttpClientResponse resp = await req.close();
      if (resp.statusCode != HttpStatus.ok) return;

      final String finalPath = await _cacheService.buildPathForKey(
        CacheKind.audio,
        cacheKey,
        extension: ext,
      );
      final File tmpFile = File('$finalPath.part_bg_${DateTime.now().microsecondsSinceEpoch}');
      await tmpFile.parent.create(recursive: true);
      final IOSink sink = tmpFile.openWrite();
      try {
        await for (final List<int> chunk in resp) {
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      final int size = await tmpFile.length();
      if (size <= 0) {
        await tmpFile.delete();
        return;
      }
      final File finalFile = File(finalPath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await tmpFile.rename(finalPath);
      await _cacheService.registerFile(
        kind: CacheKind.audio,
        cacheKey: cacheKey,
        filePath: finalPath,
        size: size,
        mimeType: mimeType,
      );
    }();

    _audioDownloadTasks[cacheKey] = task;
    try {
      await task;
    } catch (_) {
      // 后台任务失败时不影响前台播放
    } finally {
      _audioDownloadTasks.remove(cacheKey);
    }
  }

  Future<void> _downloadImageInBackground({
    required String cacheKey,
    required String realUrl,
    required String ext,
    required String mimeType,
  }) async {
    final Future<void>? existing = _imageDownloadTasks[cacheKey];
    if (existing != null) return;

    final Future<void> task = () async {
      final File? already = await _cacheService.getCachedFile(CacheKind.image, cacheKey, touch: false);
      if (already != null) return;

      final HttpClientRequest req = await _httpClient.getUrl(Uri.parse(realUrl));
      req.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/42.0.2311.135 Safari/537.36 Edge/13.10586',
      );
      req.headers.set(HttpHeaders.refererHeader, 'http://music.163.com/');
      final HttpClientResponse resp = await req.close();
      if (resp.statusCode != HttpStatus.ok) return;

      final String finalPath = await _cacheService.buildPathForKey(
        CacheKind.image,
        cacheKey,
        extension: ext,
      );
      final File tmpFile = File('$finalPath.part_bg_${DateTime.now().microsecondsSinceEpoch}');
      await tmpFile.parent.create(recursive: true);
      final IOSink sink = tmpFile.openWrite();
      try {
        await for (final List<int> chunk in resp) {
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      final int size = await tmpFile.length();
      if (size <= 0) {
        await tmpFile.delete();
        return;
      }
      final File finalFile = File(finalPath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await tmpFile.rename(finalPath);
      await _cacheService.registerFile(
        kind: CacheKind.image,
        cacheKey: cacheKey,
        filePath: finalPath,
        size: size,
        mimeType: mimeType,
      );
    }();

    _imageDownloadTasks[cacheKey] = task;
    try {
      await task;
    } catch (_) {
      // 后台任务失败时不影响前台渲染
    } finally {
      _imageDownloadTasks.remove(cacheKey);
    }
  }

  Future<void> _serveLocalFile(
    HttpRequest request,
    File file, {
    required String mimeType,
    required bool supportsRange,
  }) async {
    final int total = await file.length();
    if (total <= 0) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('File not found');
      await request.response.close();
      return;
    }

    request.response.headers.set(HttpHeaders.contentTypeHeader, mimeType);
    if (supportsRange) {
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    }

    if (!supportsRange) {
      request.response.statusCode = HttpStatus.ok;
      request.response.contentLength = total;
      await file.openRead().pipe(request.response);
      return;
    }

    final String? range = request.headers.value(HttpHeaders.rangeHeader);
    if (range == null || range.isEmpty) {
      request.response.statusCode = HttpStatus.ok;
      request.response.contentLength = total;
      await file.openRead().pipe(request.response);
      return;
    }

    final _ByteRange? parsed = _parseRangeHeader(range, total);
    if (parsed == null) {
      request.response
        ..statusCode = HttpStatus.requestedRangeNotSatisfiable
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
      await request.response.close();
      return;
    }

    request.response
      ..statusCode = HttpStatus.partialContent
      ..headers.set(HttpHeaders.contentRangeHeader, 'bytes ${parsed.start}-${parsed.end}/$total')
      ..contentLength = parsed.end - parsed.start + 1;
    await file.openRead(parsed.start, parsed.end + 1).pipe(request.response);
  }

  _ByteRange? _parseRangeHeader(String header, int total) {
    final RegExp reg = RegExp(r'^bytes=(\d*)-(\d*)$');
    final Match? m = reg.firstMatch(header.trim());
    if (m == null) return null;

    final String startRaw = m.group(1) ?? '';
    final String endRaw = m.group(2) ?? '';

    int start;
    int end;

    if (startRaw.isEmpty) {
      final int suffix = int.tryParse(endRaw) ?? 0;
      if (suffix <= 0) return null;
      if (suffix >= total) {
        start = 0;
      } else {
        start = total - suffix;
      }
      end = total - 1;
    } else {
      start = int.tryParse(startRaw) ?? -1;
      if (start < 0 || start >= total) return null;
      if (endRaw.isEmpty) {
        end = total - 1;
      } else {
        end = int.tryParse(endRaw) ?? -1;
        if (end < start) return null;
        if (end >= total) end = total - 1;
      }
    }
    return _ByteRange(start: start, end: end);
  }

  void _forwardHeaders(HttpHeaders from, HttpHeaders to) {
    from.forEach((String name, List<String> values) {
      if (name.toLowerCase() == HttpHeaders.transferEncodingHeader.toLowerCase()) {
        return;
      }
      to.set(name, values);
    });
  }

  Future<String> _getUrl(
    String songId, {
    required SongUrlLevel level,
    SongUrlEncodeType encodeType = SongUrlEncodeType.flac,
  }) async {
    final DateTime now = DateTime.now();

    _SongUrlKey? bestKey;
    for (final _SongUrlKey k in _cache.keys) {
      if (k.songId != songId || k.encodeType != encodeType) continue;
      if (k.level.index < level.index) continue;
      final _CachedUrl? cached = _cache[k];
      if (cached == null) continue;
      if (!cached.expireTime.isAfter(now.add(const Duration(seconds: 15)))) continue;
      if (bestKey == null || k.level.index > bestKey.level.index) {
        bestKey = k;
      }
    }
    if (bestKey != null) {
      return _cache[bestKey]!.url;
    }

    final _SongUrlKey key = _SongUrlKey(
      songId: songId,
      level: level,
      encodeType: encodeType,
    );

    final _CachedUrl? sameQuality = _cache[key];
    if (sameQuality != null && sameQuality.expireTime.isAfter(now.add(const Duration(seconds: 15)))) {
      return sameQuality.url;
    }

    final Future<String>? inflight = _inflightUrlRequests[key];
    if (inflight != null) {
      return inflight;
    }

    final Future<String> task = _fetchUrlFromApi(
      key: key,
      songId: songId,
      level: level,
      encodeType: encodeType,
      now: now,
    );

    _inflightUrlRequests[key] = task;
    try {
      return await task;
    } finally {
      _inflightUrlRequests.remove(key);
    }
  }

  Future<String> _fetchUrlFromApi({
    required _SongUrlKey key,
    required String songId,
    required SongUrlLevel level,
    required SongUrlEncodeType encodeType,
    required DateTime now,
  }) async {
    final DateTime? lastTime = _lastRequestTime[key];
    if (lastTime != null && now.difference(lastTime) < minInterval) {
      final _CachedUrl? cached = _cache[key];
      if (cached != null && cached.expireTime.isAfter(now)) {
        return cached.url;
      }
    }

    _lastRequestTime[key] = now;
    final SongUrlEntity? entity = await SnowfluffMusicManager().songUrl(
      ids: <String>[songId],
      level: level.name,
      encodeType: encodeType.name,
    );
    final String newUrl = (entity != null && entity.data.isNotEmpty)
        ? entity.data.first.url
        : '';
    if (newUrl.isNotEmpty) {
      _cache[key] = _CachedUrl(newUrl, now.add(const Duration(minutes: 5)));
    }
    return newUrl;
  }

  Future<void> warmupSongUrls({
    required List<String> songIds,
    SongUrlLevel level = SongUrlLevel.jyeffect,
    SongUrlEncodeType encodeType = SongUrlEncodeType.flac,
  }) async {
    if (songIds.isEmpty) return;
    final DateTime now = DateTime.now();
    final List<String> pending = <String>[];

    for (final String id in songIds.toSet()) {
      final _SongUrlKey key = _SongUrlKey(
        songId: id,
        level: level,
        encodeType: encodeType,
      );
      final _CachedUrl? cached = _cache[key];
      if (cached != null && cached.expireTime.isAfter(now.add(const Duration(seconds: 15)))) {
        continue;
      }
      pending.add(id);
    }

    if (pending.isEmpty) return;

    final SongUrlEntity? entity = await SnowfluffMusicManager().songUrl(
      ids: pending,
      level: level.name,
      encodeType: encodeType.name,
    );
    if (entity == null || entity.data.isEmpty) return;

    for (final SongUrlData item in entity.data) {
      if (item.url.isEmpty) continue;
      final _SongUrlKey key = _SongUrlKey(
        songId: item.id.toString(),
        level: level,
        encodeType: encodeType,
      );
      final DateTime expireAt = now.add(const Duration(minutes: 5));
      _cache[key] = _CachedUrl(item.url, expireAt);
      _lastRequestTime[key] = now;
    }
  }

  String proxyUrl(
    String songId, {
    SongUrlEncodeType encodeType = SongUrlEncodeType.flac,
  }) {
    return 'http://127.0.0.1:$port/song/$songId?encodeType=${encodeType.name}';
  }

  static String proxyImageUrl(
    String rawUrl, {
    String? pid,
    int? width,
    int? height,
    int port = 8848,
  }) {
    final String encoded = Uri.encodeComponent(rawUrl);
    final StringBuffer sb = StringBuffer('http://127.0.0.1:$port/image?url=$encoded');
    if (pid != null && pid.isNotEmpty) {
      sb.write('&pid=$pid');
    }
    if (width != null && width > 0) {
      sb.write('&w=$width');
    }
    if (height != null && height > 0) {
      sb.write('&h=$height');
    }
    return sb.toString();
  }

  String _audioCacheKey(
    String songId,
    SongUrlLevel level,
    SongUrlEncodeType encodeType,
  ) {
    return 'song_${songId}_${level.name}_${encodeType.name}';
  }

  /// 查找本地 >= [requestedLevel] 的最高音质缓存，找不到返回 null
  /// 命中更高音质时直接复用，不再下载低音质版本
  Future<File?> _findBestCachedAudio(
    String songId,
    SongUrlLevel requestedLevel,
    SongUrlEncodeType encodeType,
  ) async {
    final int reqIdx = SongUrlLevel.values.indexOf(requestedLevel);
    for (int i = SongUrlLevel.values.length - 1; i >= reqIdx; i--) {
      final SongUrlLevel candidate = SongUrlLevel.values[i];
      final String key = _audioCacheKey(songId, candidate, encodeType);
      final File? f = await _cacheService.getCachedFile(CacheKind.audio, key);
      if (f != null) return f;
    }
    return null;
  }

  int _resolveImageWidth(String realUrl, Uri proxyUri) {
    final int direct = int.tryParse(proxyUri.queryParameters['w'] ?? '') ?? 0;
    if (direct > 0) return direct;
    final Uri? uri = Uri.tryParse(realUrl);
    final String param = uri?.queryParameters['param'] ?? '';
    final RegExp m = RegExp(r'^(\d+)y(\d+)$');
    final Match? hit = m.firstMatch(param);
    if (hit == null) return 0;
    return int.tryParse(hit.group(1) ?? '') ?? 0;
  }

  int _resolveImageHeight(String realUrl, Uri proxyUri) {
    final int direct = int.tryParse(proxyUri.queryParameters['h'] ?? '') ?? 0;
    if (direct > 0) return direct;
    final Uri? uri = Uri.tryParse(realUrl);
    final String param = uri?.queryParameters['param'] ?? '';
    final RegExp m = RegExp(r'^(\d+)y(\d+)$');
    final Match? hit = m.firstMatch(param);
    if (hit == null) return 0;
    return int.tryParse(hit.group(2) ?? '') ?? 0;
  }

  String _extensionFromUrl(String url, {required String fallback}) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return fallback;
    return _extensionFromPath(uri.path, fallback: fallback);
  }

  String _extensionFromPath(String path, {required String fallback}) {
    final int idx = path.lastIndexOf('.');
    if (idx < 0 || idx >= path.length - 1) return fallback;
    final String ext = path.substring(idx + 1).toLowerCase();
    if (ext.isEmpty) return fallback;
    if (ext.length > 6) return fallback;
    return ext;
  }

  String _audioMimeFromExt(String ext) {
    switch (ext.toLowerCase()) {
      case 'mp3':
        return 'audio/mpeg';
      case 'aac':
      case 'm4a':
        return 'audio/aac';
      case 'flac':
        return 'audio/flac';
      case 'ogg':
        return 'audio/ogg';
      case 'wav':
        return 'audio/wav';
      default:
        return 'application/octet-stream';
    }
  }

  String _imageMimeFromExt(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'application/octet-stream';
    }
  }
}

class _ByteRange {
  final int start;
  final int end;

  const _ByteRange({
    required this.start,
    required this.end,
  });
}
