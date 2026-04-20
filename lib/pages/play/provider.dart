import 'dart:async';
import 'package:snowfluff/common/media_cache_service.dart';
import 'package:snowfluff/common/settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:ncm_api/api/agent.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'provider.g.dart';

const int _kLyricComputeThresholdChars = 8000;
const Duration _kLyricComputeTimeout = Duration(seconds: 2);

class LyricLine {
  final String text; // 原文
  final String? ttext; // 翻译
  final Duration time; // 时间戳
  LyricLine({
    required this.text,
    this.ttext,
    required this.time
  });
}

@riverpod
Future<List<LyricLine>> mediaLyric(Ref ref, int songId) async {
  final link = ref.keepAlive();
  Timer? disposeTimer;
  void startDisposeTimer() {
    disposeTimer?.cancel();
    disposeTimer = Timer(const Duration(seconds: 60), () {
      link.close();
    });
  }
  void cancelDisposeTimer() {
    disposeTimer?.cancel();
  }
  ref.onCancel(startDisposeTimer); // 最后一个监听结束时开始计时
  ref.onResume(cancelDisposeTimer);
  ref.onDispose(cancelDisposeTimer);
  return _fetchLyrics(songId);
}

Future<List<LyricLine>> _fetchLyrics(int songId) async {
  if (songId <= 0) return [];
  final MediaCacheService cacheService = MediaCacheService();
  try {
    final LyricCacheData? cached = await cacheService.readLyric(songId);
    if (cached != null) {
      return _applyInstrumentalFilter(
        await _parseLyricsAdaptive(cached.lrc, cached.tlyric),
      );
    }

    Future<List<LyricLine>> doFetch() async {
      final result = await SnowfluffMusicManager().songLyric(id: songId).timeout(const Duration(seconds: 5));
      if (result == null || result.code != 200) return [];
      final rawLrc = result.lrc?.lyric ?? '';
      final rawTLrc = result.tlyric?.lyric ?? '';
      if (rawLrc.isEmpty && rawTLrc.isEmpty) return []; // 几乎不可能只有翻译没有原文
      final parsed = _applyInstrumentalFilter(
        await _parseLyricsAdaptive(rawLrc, rawTLrc),
      );
      unawaited(
        _writeLyricCacheBestEffort(cacheService, songId, rawLrc, rawTLrc),
      );
      return parsed;
    }
    try {
      return await doFetch();
    } on TimeoutException {
      return await doFetch(); // 超时重试一次，再超时或出错由外层catch静默返回[]
    }
  } catch (_) {
    return [];
  }
}

List<LyricLine> _applyInstrumentalFilter(List<LyricLine> lyrics) {
  if (!SettingsService.filterInstrumentalLyrics) return lyrics;
  if (lyrics.isEmpty) return lyrics;
  if (lyrics.last.text.startsWith('纯音乐')) return [];
  return lyrics;
}

Future<List<LyricLine>> _parseLyricsAdaptive(String lrc, String tlrc) {
  final textSize = lrc.length + tlrc.length;
  if (textSize <= _kLyricComputeThresholdChars) {
    return Future.value(_parseLyrics(lrc, tlrc));
  }
  return compute(_parseLyricsInBackground, <String>[
    lrc,
    tlrc,
  ]).timeout(_kLyricComputeTimeout);
}

Future<void> _writeLyricCacheBestEffort(
  MediaCacheService cacheService,
  int songId,
  String lrc,
  String tlyric,
) async {
  try {
    await cacheService.writeLyric(songId, lrc: lrc, tlyric: tlyric);
  } catch (_) {
    // cache写入失败不影响歌词展示
  }
}

List<LyricLine> _parseLyricsInBackground(List<String> payload) {
  final lrc = payload.isNotEmpty ? payload[0] : '';
  final tlrc = payload.length > 1 ? payload[1] : '';
  return _parseLyrics(lrc, tlrc);
}

List<LyricLine> _parseLyrics(String lrc, String tlrc) {
  if (lrc.isEmpty) return [];
  final RegExp regExp = RegExp(r'\[(\d+):(\d+\.?\d*)\](.*)');
  final Map<Duration, String> mainMap = {};
  for (final line in lrc.split('\n')) {
    final match = regExp.firstMatch(line);
    if (match != null) {
      final text = match.group(3)?.trim() ?? '';
      if (text.isNotEmpty) {
        final duration = Duration(
          minutes: int.parse(match.group(1)!),
          milliseconds: (double.parse(match.group(2)!) * 1000).toInt(),
        );
        mainMap[duration] = text;
      }
    }
  }
  final Map<Duration, String> transMap = {};
  if (tlrc.isNotEmpty) {
    for (final line in tlrc.split('\n')) {
      final match = regExp.firstMatch(line);
      if (match != null) {
        final duration = Duration(
          minutes: int.parse(match.group(1)!),
          milliseconds: (double.parse(match.group(2)!) * 1000).toInt(),
        );
        transMap[duration] = match.group(3)?.trim() ?? '';
      }
    }
  }
  final result = mainMap.entries.map((entry) {
    return LyricLine(
      time: entry.key,
      text: entry.value,
      ttext: transMap[entry.key],
    );
  }).toList();
  result.sort((a,b) => a.time.compareTo(b.time));
  return result;
}
