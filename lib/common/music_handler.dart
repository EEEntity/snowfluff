import 'dart:async';
import 'package:snowfluff/common/local_proxy_service.dart';
import 'package:snowfluff/common/media_cache_service.dart';
import 'package:snowfluff/common/playback_state_cache_service.dart';
import 'package:snowfluff/common/settings_service.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:ncm_api/api/agent.dart';
import 'package:ncm_api/api/recommend.dart';
import 'package:ncm_api/api/song.dart';

class SnowfluffMusicHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  static const int _persistIntervalMs = 2000;

  int _lastPersistMs = 0;
  bool _isRestoringFromCache = false;
  bool _isRestartingLoopOne = false;
  bool _isPreparingPlay = false;
  int? _preparingPlayTargetIndex;
  int? _cachedBackgroundColorArgb;

  // 随机播放：索引映射
  bool _shuffleEnabled = false;
  List<int> _shuffleOrder = const [];
  int _shufflePosition = 0;

  // 私人FM
  static const String kFMQueueTitle = '__personal_fm__';
  bool _isFMMode = false;
  bool _fmFetching = false;
  final List<MediaItem> _fmPrefetchBuffer = [];

  // 私有构造函数
  SnowfluffMusicHandler._internal() {
    // 播放器状态同步到audio_service
    _audioPlayer.playerStateStream.listen((PlayerState state) {
      var playing = state.playing;
      if (playing && _isPreparingPlay) {
        _isPreparingPlay = false;
        _preparingPlayTargetIndex = null;
      }
      playbackState.add(
        playbackState.value.copyWith(
          playing: playing,
          processingState: const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[state.processingState]!,
          systemActions: const {MediaAction.seek},
          androidCompactActionIndices: _isFMMode ? const [0, 1] : const [0, 1, 2],
          controls: _isFMMode
              ? [
                  playing ? MediaControl.pause : MediaControl.play,
                  MediaControl.skipToNext,
                ]
              : [
                  MediaControl.skipToPrevious,
                  playing ? MediaControl.pause : MediaControl.play,
                  MediaControl.skipToNext,
                ],
          // repeatMode: AudioServiceRepeatMode.all,
          // shuffleMode: AudioServiceShuffleMode.none,
        ),
      );
      if (!playing || state.processingState == ProcessingState.completed) {
        unawaited(_persistPlaybackState(force: true));
      }
      if (state.playing &&
          state.processingState == ProcessingState.completed &&
          _audioPlayer.loopMode == LoopMode.one) {
        unawaited(_recoverLoopOneOnCompletion());
      }
    });
    _audioPlayer.currentIndexStream.listen((index) {
      // media_kit在idle->load期间可能短暂发出错误索引(0)，准备播放时忽略该瞬态值
      if (_isPreparingPlay &&
          _preparingPlayTargetIndex != null &&
          !_audioPlayer.playing &&
          index != _preparingPlayTargetIndex) {
        return;
      }
      // FM模式：推进到新index时删除已播放项并触发预取(恢复缓存期间跳过)
      if (_isFMMode && !_isRestoringFromCache && index != null && index >= 0) {
        if (index > 0) {
          // 自动推进到非0位置：清理前缀
          unawaited(_fmAdvancedToIndex(index));
          return; // _fmAdvancedToIndex内部会更新playbackState/mediaItem/persist
        } else if (queue.value.length < 2 && !_fmFetching) {
          // 回绕到0（只剩1首循环）或刚进入FM：补充预取
          unawaited(_fmAppendNext());
        }
      }
      // currentIndex可能短暂变为null，保留上一条有效queueIndex，避免回退到0
      if (index != null && index >= 0 && playbackState.value.queueIndex != index) {
        // 切歌时同步位置，避免暂停态因positionStream不推流而残留上一首进度
        // 播放状态下自动/手动切歌时，切换瞬间底层position可能仍残留上一首末尾值
        // 若直接广播会导致进度条短暂跳到末尾再归零(抖动)；新歌必然从0开始，直接写0
        // 暂停状态下positionStream不推流，才需要读_audioPlayer.position
        final Duration syncPosition = _audioPlayer.playing ? Duration.zero : _audioPlayer.position;
        playbackState.add(
          playbackState.value.copyWith(
            queueIndex: index,
            updatePosition: syncPosition,
          ),
        );
        if (queue.value.isNotEmpty && index < queue.value.length) {
          mediaItem.add(queue.value[index]);
        }
      }
      unawaited(_persistPlaybackState(force: true));
      // 仅在“已处于播放中”且切到新歌时检查灰色歌曲
      if (_audioPlayer.playing && index != null && index >= 0) {
        unawaited(_handleGreyStartIfNeeded());
      }
    });
    Duration lastBroadcastPosition = Duration.zero;
    Duration lastBroadcastBuffered = Duration.zero;
    DateTime lastPositionAt = DateTime.fromMillisecondsSinceEpoch(0);
    DateTime lastBufferedAt = DateTime.fromMillisecondsSinceEpoch(0);
    _audioPlayer.positionStream.listen((position) {
      // 只在播放时上报高频进度，暂停不推流
      if (!_audioPlayer.playing) return;
      final now = DateTime.now();
      final posDelta = position - lastBroadcastPosition;
      final timeDelta = now.difference(lastPositionAt);
      // 双阈值：时间间隔/进度变化量
      if (timeDelta < const Duration(milliseconds: 10) &&
          posDelta.abs() < const Duration(milliseconds: 10)) {
        return;
      }
      lastBroadcastPosition = position;
      lastPositionAt = now;
      playbackState.add(playbackState.value.copyWith(updatePosition: position));
    });
    _audioPlayer.bufferedPositionStream.listen((buffered) {
      final now = DateTime.now();
      final bufferDelta = buffered - lastBroadcastBuffered;
      final timeDelta = now.difference(lastBufferedAt);
      // 缓冲进度降低到约3Hz
      // 后续显示缓冲进度可能有用
      if (timeDelta < const Duration(milliseconds: 320) &&
          bufferDelta.abs() < const Duration(milliseconds: 320)) {
        return;
      }
      lastBroadcastBuffered = buffered;
      lastBufferedAt = now;
      playbackState.add(
        playbackState.value.copyWith(bufferedPosition: buffered),
      );
    });
    _audioPlayer.loopModeStream.listen((loopMode) {
      playbackState.add(
        playbackState.value.copyWith(
          repeatMode: _repeatModeFromLoopMode(loopMode),
        ),
      );
      unawaited(_persistPlaybackState(force: true));
    });
    // 不监听shuffleModeEnabledStream：shuffle完全由应用层changeLoopMode管理
    // 底层just_audio/media_kit内部可能在改变loopMode时异步触发false
    // 监听可能会覆盖手动设置的shuffleMode，导致UI状态错误
    _audioPlayer.setShuffleModeEnabled(false); // 底层保持顺序播放，不依赖其shuffle
    _audioPlayer.setLoopMode(LoopMode.one); // 默认单曲循环
  }
  static final SnowfluffMusicHandler _instance = SnowfluffMusicHandler._internal();
  factory SnowfluffMusicHandler() => _instance;
  final AudioPlayer _audioPlayer = AudioPlayer();
  int? get cachedBackgroundColorArgb => _cachedBackgroundColorArgb;
  bool get shuffleEnabled => _shuffleEnabled;
  bool get isFMMode => _isFMMode;

  /// 以 [currentIdx] 为起点构建随机播放顺序
  void _buildShuffleOrder(int currentIdx) {
    final int len = queue.value.length;
    if (len == 0) {
      _shuffleOrder = const [];
      _shufflePosition = 0;
      return;
    }
    final List<int> others = List<int>.generate(len, (i) => i)
      ..remove(currentIdx)
      ..shuffle();
    _shuffleOrder = [currentIdx, ...others];
    _shufflePosition = 0;
  }

  Future<void> updateBackgroundColorCache(Color color) async {
    final int argb = color.toARGB32();
    if (_cachedBackgroundColorArgb == argb) return;
    _cachedBackgroundColorArgb = argb;
    await PlaybackStateCacheService().saveBackgroundColorArgb(argb);
    unawaited(_persistPlaybackState(force: true));
  }

  int? _lastPlayStartCheckedIndex; // 上次检查到的播放开始的索引，用于避免重复更新mediaItem
  bool _isHandlingGreyStart = false; // 防重入，避免重复skip
  Future<void> init() async {
    AudioSession session = await AudioSession.instance;
    session.configure(const AudioSessionConfiguration.speech());
  }

  /// 更新播放列表
  @override
  Future<void> updateQueue(
    List<MediaItem> songs, {
    int index = 0,
    String queueName = '',
    bool save = true,
    Duration? position,
    SongUrlLevel? level,
    SongUrlEncodeType encodeType = SongUrlEncodeType.flac,
    bool warmup = true,
    bool autoPlay = true,
  }) async {
    if (songs.isEmpty) return;
    // 非FM队列调用时退出FM模式
    if (_isFMMode && queueName != kFMQueueTitle) {
      _exitFMMode();
    }
    final targetLevel = level ?? SettingsService.musicQuality;
    final playlist = <ProgressiveAudioSource>[];
    if (queueTitle.value == queueName && queue.value.isNotEmpty) {
      await _audioPlayer.seek(position ?? Duration.zero, index: index);
    } else {
      queueTitle.value = queueName;
      _lastPlayStartCheckedIndex = null; // 切歌单重置灰色歌曲检查
      queue.add(songs);
      if (_shuffleEnabled) {
        _buildShuffleOrder(index);
      }
      // 先做URL预热，批量拿地址
      if (warmup) {
        await LocalProxyService().warmupSongUrls(
          songIds: songs.map((e) => e.id).toList(),
          level: targetLevel,
          encodeType: encodeType,
        );
      }
      for (var song in songs) {
        playlist.add(
          ProgressiveAudioSource(
            Uri.parse(
              LocalProxyService().proxyUrl(
                song.id,
                encodeType: encodeType,
              ),
            ),
            tag: song.id,
          ),
        );
      }
      await _audioPlayer.setAudioSources(
        playlist,
        initialIndex: index,
        initialPosition: position,
        preload: false,
      );
      await _audioPlayer.seek(position ?? Duration.zero, index: index);
    }
    if (index >= 0 && index < songs.length) {
      mediaItem.add(songs[index]);
      playbackState.add(playbackState.value.copyWith(queueIndex: index));
    }
    _syncPositionToPlaybackState(position ?? _audioPlayer.position);
    if (autoPlay) {
      await play();
    } else {
      await pause();
    }
    if (save) {
      unawaited(_persistPlaybackState(force: true));
    }
  }

  /// 播放
  @override
  Future<void> play() async {
    // 播放器处于idle(preload=false/意外复位)时，先同步底层状态再播放
    await _restorePlayerIfIdle();
    final canPlay = await _handleGreyStartIfNeeded();
    if (!canPlay) {
      _isPreparingPlay = false;
      _preparingPlayTargetIndex = null;
      return;
    }
    await _audioPlayer.play();
  }

  /// 定位
  @override
  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
    _syncPositionToPlaybackState(position);
    unawaited(_persistPlaybackState(force: true));
  }

  /// 暂停
  @override
  Future<void> pause() async {
    await _audioPlayer.pause();
    _syncPositionToPlaybackState(_audioPlayer.position);
    unawaited(_persistPlaybackState(force: true));
  }

  /// 停止
  @override
  Future<void> stop() async {
    await _audioPlayer.stop();
    _syncPositionToPlaybackState(Duration.zero);
    unawaited(_persistPlaybackState(force: true));
  }

  /// 播放/暂停切换
  Future<void> toggle() async {
    _audioPlayer.playing ? pause() : play();
  }

  /// 下一首
  @override
  Future<void> skipToNext() async {
    if (_isFMMode) {
      await _skipToNextFM();
      return;
    }
    final int queueLen = queue.value.length;
    if (_shuffleEnabled && queueLen > 1) {
      _shufflePosition++;
      if (_shufflePosition >= _shuffleOrder.length) {
        // 耗尽，打乱全部索引重新开始
        _shuffleOrder = List<int>.generate(queueLen, (i) => i)..shuffle();
        _shufflePosition = 0;
      }
      await _audioPlayer.seek(Duration.zero, index: _shuffleOrder[_shufflePosition]);
    } else if (_audioPlayer.loopMode == LoopMode.one && queueLen > 1) {
      final int cur = _audioPlayer.currentIndex ?? playbackState.value.queueIndex ?? 0;
      await _audioPlayer.seek(Duration.zero, index: (cur + 1) % queueLen);
    } else {
      await _audioPlayer.seekToNext();
    }
    unawaited(_persistPlaybackState(force: true));
  }

  /// 上一首
  @override
  Future<void> skipToPrevious() async {
    final int queueLen = queue.value.length;
    if (_shuffleEnabled && queueLen > 1) {
      if (_shufflePosition > 0) {
        _shufflePosition--;
        await _audioPlayer.seek(Duration.zero, index: _shuffleOrder[_shufflePosition]);
      } else {
        // 已在随机历史起点，重播当前歌曲
        await _audioPlayer.seek(Duration.zero);
      }
    } else if (_audioPlayer.loopMode == LoopMode.one && queueLen > 1) {
      final int cur = _audioPlayer.currentIndex ?? playbackState.value.queueIndex ?? 0;
      await _audioPlayer.seek(Duration.zero, index: (cur - 1 + queueLen) % queueLen);
    } else {
      await _audioPlayer.seekToPrevious();
    }
    unawaited(_persistPlaybackState(force: true));
  }

  /// 私人FM - 不感兴趣，并跳到下一首
  Future<void> personalFMTrash() async {
    final String? songId = mediaItem.value?.id;
    if (songId == null) return;
    final int? id = int.tryParse(songId);
    if (id == null) return;
    await SnowfluffMusicManager().personalFMTrash(id: id);
    await skipToNext();
  }

  /// 切换循环/随机模式：列表循环 -> 单曲循环 -> 随机播放 -> 列表循环
  Future<void> changeLoopMode() async {
    if (_shuffleEnabled) {
      // 随机 -> 列表循环
      _shuffleEnabled = false;
      _shuffleOrder = const [];
      playbackState.add(playbackState.value.copyWith(
        shuffleMode: AudioServiceShuffleMode.none,
      ));
      await _audioPlayer.setLoopMode(LoopMode.all);
    } else if (_audioPlayer.loopMode == LoopMode.all) {
      // 列表循环 -> 单曲循环
      await _audioPlayer.setLoopMode(LoopMode.one);
    } else {
      // 单曲循环 -> 随机播放
      await _audioPlayer.setLoopMode(LoopMode.all);
      _shuffleEnabled = true;
      final int cur = _audioPlayer.currentIndex ?? playbackState.value.queueIndex ?? 0;
      _buildShuffleOrder(cur);
      playbackState.add(playbackState.value.copyWith(
        shuffleMode: AudioServiceShuffleMode.all,
      ));
    }
    unawaited(_persistPlaybackState(force: true));
  }

  /// 设置shuffle开关
  Future<void> setShuffleEnabled(bool enabled) async {
    await _audioPlayer.setShuffleModeEnabled(enabled);
    if (enabled) {
      // shuffle()生成随机播放列表
      await _audioPlayer.shuffle();
    }
  }

  /// 从队列移除指定索引的歌曲
  Future<void> removeFromQueue(int index) async {
    final currentQueue = queue.value;
    if (index < 0 || index >= currentQueue.length) return;
    currentQueue.removeAt(index);
    if (currentQueue.isEmpty) {
      queue.add(const <MediaItem>[]);
      _lastPlayStartCheckedIndex = null;
      await stop();
      await PlaybackStateCacheService().clear();
      return;
    }
    queue.add(List.from(currentQueue));
    // 如果移除的是当前播放歌曲，自动跳到下一首
    final currentIndex = playbackState.value.queueIndex ?? 0;
    if (index == currentIndex && currentQueue.isNotEmpty) {
      final newIndex = index >= currentQueue.length
          ? currentQueue.length - 1
          : index;
      await _audioPlayer.seek(Duration.zero, index: newIndex);
    } else if (index < currentIndex) {
      // 移除当前歌曲之前的歌曲，调整queueIndex
      playbackState.value.copyWith(queueIndex: currentIndex - 1);
    }
    unawaited(_persistPlaybackState(force: true));
  }

  /// 快速跳转到队列的某一首歌
  Future<void> skipToQueueIndex(int index) async {
    if (index < 0 || index >= queue.value.length) return;
    await _audioPlayer.seek(Duration.zero, index: index);
    unawaited(_persistPlaybackState(force: true));
  }

  /// 清空队列
  Future<void> clearQueue() async {
    queue.add(const <MediaItem>[]);
    queueTitle.value = '';
    mediaItem.add(null);
    _lastPlayStartCheckedIndex = null; // 清空队列重置灰色歌曲检查
    _shuffleEnabled = false;
    _shuffleOrder = const [];
    _shufflePosition = 0;
    await stop();
    await PlaybackStateCacheService().clear();
  }

  /// 清空
  Future<void> dispose() async {
    await _persistPlaybackState(force: true);
    await _audioPlayer.dispose();
  }

  Future<void> restoreFromCache() async {
    if (_isRestoringFromCache) return;
    _isRestoringFromCache = true;
    try {
      final PlaybackStateCacheService cacheService =
          PlaybackStateCacheService();
      final int? cachedBg = await cacheService.loadBackgroundColorArgb();
      if (cachedBg != null) {
        _cachedBackgroundColorArgb = cachedBg;
      }
      final PlaybackCacheState? cached = await cacheService.load();
      if (cached == null || cached.queueSongs.isEmpty) return;
      if (cached.backgroundColorArgb != null) {
        _cachedBackgroundColorArgb = cached.backgroundColorArgb;
      }

      final List<int> songIds = cached.queueSongs
          .map((PlaybackCachedSong e) => e.id)
          .where((int id) => id > 0)
          .toList(growable: false);
      if (songIds.isEmpty) return;

      final bool hasArtistMeta = cached.queueSongs.any(
        (PlaybackCachedSong e) =>
            e.artist.trim().isNotEmpty || e.artistIds.isNotEmpty,
      );

      final List<MediaItem> songs = hasArtistMeta
          ? _buildMediaItemsFromCache(cached.queueSongs)
          : await _buildMediaItemsFromIds(songIds);
      if (songs.isEmpty) return;

      int targetIndex = cached.currentIndex;
      if (targetIndex < 0 || targetIndex >= songs.length) {
        if (cached.currentSongId > 0) {
          final int hit = songs.indexWhere(
            (MediaItem e) => int.tryParse(e.id) == cached.currentSongId,
          );
          targetIndex = hit >= 0 ? hit : 0;
        } else {
          targetIndex = 0;
        }
      }

      final LoopMode restoredLoopMode = _loopModeFromName(cached.loopMode);
      await _audioPlayer.setLoopMode(restoredLoopMode);
      // 在updateQueue之前设置，以便updateQueue内部能正确构建shuffleOrder和FM判断
      _shuffleEnabled = cached.shuffleEnabled;
      _isFMMode = cached.isFMMode;
      await updateQueue(
        songs,
        index: targetIndex,
        queueName: cached.queueName,
        save: false,
        warmup: false,
        autoPlay: false,
      );
      if (_shuffleEnabled) {
        playbackState.add(playbackState.value.copyWith(
          shuffleMode: AudioServiceShuffleMode.all,
        ));
      }
      if (_isFMMode && songs.length < 2) {
        // FM模式恢复时队列不足，主动预取补充
        unawaited(_fmAppendNext());
      }
      _syncPositionToPlaybackState(Duration.zero);
    } catch (_) {
      // Ignore restore errors
    } finally {
      _isRestoringFromCache = false;
    }
  }

  Future<List<MediaItem>> _buildMediaItemsFromIds(List<int> songIds) async {
    if (songIds.isEmpty) return const <MediaItem>[];

    final SongDetailEntity? detail = await SnowfluffMusicManager().songDetail(
      ids: songIds,
    );
    final Map<int, SongDetailSongs> byId = <int, SongDetailSongs>{};
    for (final SongDetailSongs song
        in detail?.songs ?? const <SongDetailSongs>[]) {
      byId[song.id] = song;
    }

    return songIds
        .map((int id) {
          final SongDetailSongs? song = byId[id];
          if (song == null) {
            return _buildFallbackMediaItem(id);
          }
          final String artist = song.ar
              .map((SongDetailSongsAr e) => e.name)
              .toList()
              .join(' / ');
          final List<int> artistIds = song.ar
              .map((SongDetailSongsAr e) => e.id)
              .toList(growable: false);
          final String rawPic = song.al?.picUrl ?? '';
          final String artProxy = rawPic.isEmpty
              ? ''
              : LocalProxyService.proxyImageUrl(
                  rawPic,
                  pid: song.al?.pic.toString(),
                );
          return MediaItem(
            id: song.id.toString(),
            title: song.name,
            duration: Duration(milliseconds: song.dt),
            artist: artist,
            artUri: artProxy.isEmpty ? null : Uri.parse(artProxy),
            extras: <String, dynamic>{'artistIds': artistIds},
          );
        })
        .toList(growable: false);
  }

  List<MediaItem> _buildMediaItemsFromCache(List<PlaybackCachedSong> songs) {
    if (songs.isEmpty) return const <MediaItem>[];
    return songs
        .map((PlaybackCachedSong song) {
          final String art = song.artUri;
          return MediaItem(
            id: song.id.toString(),
            title: song.title,
            duration: Duration(milliseconds: song.durationMs),
            artist: song.artist,
            artUri: art.isEmpty ? null : Uri.parse(art),
            extras: <String, dynamic>{'artistIds': song.artistIds},
          );
        })
        .toList(growable: false);
  }

  MediaItem _buildFallbackMediaItem(int songId) {
    return MediaItem(
      id: songId.toString(),
      title: '歌曲$songId',
      duration: Duration.zero,
      artist: '',
      artUri: null,
      extras: const <String, dynamic>{'artistIds': <int>[]},
    );
  }

  // 私人FM
  /// 进入私人FM模式：获取初始歌曲并开始播放
  Future<void> enterFMMode() async {
    _isFMMode = false;
    _fmFetching = false;
    _fmPrefetchBuffer.clear();
    final List<MediaItem> songs = await _fmFetchFilledSongs(needed: 2);
    if (songs.isEmpty) return;
    // FM使用LoopMode.all：单首时skipToNext会重播当前，无需特殊处理
    await _audioPlayer.setLoopMode(LoopMode.all);
    await updateQueue(
      songs,
      index: 0,
      queueName: kFMQueueTitle,
      save: true,
      autoPlay: true,
    );
    _isFMMode = true;
  }

  /// 退出FM模式（内部静默调用）
  void _exitFMMode() {
    _isFMMode = false;
    _fmPrefetchBuffer.clear();
    _fmFetching = false;
  }

  /// FM模式下的下一首
  Future<void> _skipToNextFM() async {
    final int len = queue.value.length;
    if (len == 0) return;
    // 只剩1首（预取还没回来）：重播当前
    if (len == 1) {
      await _audioPlayer.seek(Duration.zero, index: 0);
      unawaited(_persistPlaybackState(force: true));
      return;
    }
    // 跳到index 1；清理和预取由currentIndexStream统一处理
    await _audioPlayer.seek(Duration.zero, index: 1);
    unawaited(_persistPlaybackState(force: true));
  }

  /// currentIndexStream中FM模式推进到newIndex时的清理逻辑
  Future<void> _fmAdvancedToIndex(int newIndex) async {
    if (newIndex <= 0) return;
    final List<MediaItem> updated = queue.value.sublist(newIndex);
    // 先更新逻辑队列/mediaItem/playbackState，再执行底层 removeAudioSourceAt：
    // removeAudioSourceAt 会触发 currentIndexStream(0)，若此时 queue.value 仍是旧值，
    // 正常代码路径会把 mediaItem 临时倒退到已播完的歌曲，引起 UI 闪烁和错误歌词请求
    queue.add(updated);
    if (updated.isNotEmpty) {
      mediaItem.add(updated[0]);
    }
    playbackState.add(playbackState.value.copyWith(queueIndex: 0));
    // 临时持有 _fmFetching，阻止 removeAudioSourceAt 触发的 currentIndexStream(0)
    // 在移除过程中重复调用 _fmAppendNext
    _fmFetching = true;
    try {
      for (int i = 0; i < newIndex; i++) {
        await _audioPlayer.removeAudioSourceAt(0);
      }
    } finally {
      _fmFetching = false;
    }
    if (updated.length < 2) {
      unawaited(_fmAppendNext());
    }
    unawaited(_persistPlaybackState(force: true));
  }

  /// 从预取缓冲或API取一首新歌，追加到播放队列末尾
  Future<void> _fmAppendNext() async {
    if (_fmFetching || !_isFMMode) return;
    _fmFetching = true;
    try {
      if (_fmPrefetchBuffer.isEmpty) {
        final List<MediaItem> fetched = await _fmFetchFilledSongs(needed: 3);
        _fmPrefetchBuffer.addAll(fetched);
      }
      if (_fmPrefetchBuffer.isEmpty || !_isFMMode) return;
      final MediaItem next = _fmPrefetchBuffer.removeAt(0);
      final String songId = next.id;
      queue.add([...queue.value, next]);
      await _audioPlayer.addAudioSource(
        ProgressiveAudioSource(
          Uri.parse(
            LocalProxyService().proxyUrl(
              songId,
              encodeType: SongUrlEncodeType.flac,
            ),
          ),
          tag: songId,
        ),
      );
      // warmup新歌URL
      unawaited(LocalProxyService().warmupSongUrls(
        songIds: [songId],
        level: SettingsService.musicQuality,
        encodeType: SongUrlEncodeType.flac,
      ));
      unawaited(_persistPlaybackState(force: true));
    } catch (_) {
      // Ignore fetch/append errors; user can retry by pressing next
    } finally {
      _fmFetching = false;
    }
  }

  /// 从API获取有效（非灰色）歌曲，直到凑满needed首，最多3轮请求
  Future<List<MediaItem>> _fmFetchFilledSongs({required int needed}) async {
    final List<MediaItem> result = [];
    int retries = 0;
    const int maxRetries = 3;
    while (result.length < needed && retries < maxRetries) {
      retries++;
      try {
        final PersonalFMEntity? entity = await SnowfluffMusicManager()
            .personalFM()
            .timeout(const Duration(seconds: 5));
        final List<PersonalFMSong> songs = entity?.data ?? const [];
        if (songs.isEmpty) break;
        for (final PersonalFMSong song in songs) {
          if (result.length >= needed) break;
          if ((song.privilege?.st ?? 0) < 0) continue; // 跳过灰色歌曲
          result.add(_personalFMSongToMediaItem(song));
        }
      } catch (_) {
        break;
      }
    }
    return result;
  }

  /// 将PersonalFMSong转为MediaItem
  MediaItem _personalFMSongToMediaItem(PersonalFMSong song) {
    final String rawArt = song.album?.picUrl ?? '';
    final String identity = song.id > 0
        ? song.id.toString()
        : MediaCacheService.safeImageIdentityFromUrl(rawArt);
    return MediaItem(
      id: song.id.toString(),
      title: song.name,
      duration: Duration(milliseconds: song.duration),
      artist: song.artists.map((PersonalFMSongArtist a) => a.name).join(' / '),
      artUri: rawArt.isEmpty
          ? null
          : Uri.parse(LocalProxyService.proxyImageUrl(rawArt, pid: identity)),
      extras: <String, dynamic>{
        'artistIds': song.artists
            .map((PersonalFMSongArtist a) => a.id)
            .toList(growable: false),
      },
    );
  }

  Future<void> _persistPlaybackState({bool force = false}) async {
    if (_isRestoringFromCache) return;
    final List<MediaItem> currentQueue = queue.value;
    if (currentQueue.isEmpty) return;

    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!force && nowMs - _lastPersistMs < _persistIntervalMs) {
      return;
    }

    int currentIndex =
        _audioPlayer.currentIndex ?? playbackState.value.queueIndex ?? 0;
    if (currentIndex < 0) {
      currentIndex = 0;
    }
    if (currentIndex >= currentQueue.length) {
      currentIndex = currentQueue.length - 1;
    }

    final int currentSongId = int.tryParse(currentQueue[currentIndex].id) ?? 0;
    final List<PlaybackCachedSong> queueSongs = currentQueue
        .map<PlaybackCachedSong?>((MediaItem item) {
          final int id = int.tryParse(item.id) ?? 0;
          if (id <= 0) return null;
          final dynamic rawArtistIds = item.extras?['artistIds'];
          final List<int> artistIds = rawArtistIds is List
              ? rawArtistIds
                    .map((dynamic e) => int.tryParse(e.toString()) ?? 0)
                    .where((int e) => e > 0)
                    .toList(growable: false)
              : const <int>[];
          return PlaybackCachedSong(
            id: id,
            title: item.title,
            artist: item.artist ?? '',
            durationMs: item.duration?.inMilliseconds ?? 0,
            artUri: item.artUri?.toString() ?? '',
            artistIds: artistIds,
          );
        })
        .whereType<PlaybackCachedSong>()
        .toList(growable: false);
    if (queueSongs.isEmpty) return;
    _lastPersistMs = nowMs;

    await PlaybackStateCacheService().save(
      PlaybackCacheState(
        queueSongs: queueSongs,
        currentIndex: currentIndex,
        currentSongId: currentSongId,
        backgroundColorArgb: _cachedBackgroundColorArgb,
        loopMode: _audioPlayer.loopMode.name,
        wasPlaying: _audioPlayer.playing,
        queueName: queueTitle.value,
        shuffleEnabled: _shuffleEnabled,
        isFMMode: _isFMMode,
      ),
    );
  }

  AudioServiceRepeatMode _repeatModeFromLoopMode(LoopMode loopMode) {
    return switch (loopMode) {
      LoopMode.all => AudioServiceRepeatMode.all,
      LoopMode.one => AudioServiceRepeatMode.one,
      LoopMode.off => AudioServiceRepeatMode.none,
    };
  }

  LoopMode _loopModeFromName(String raw) {
    final String normalized = raw.trim().toLowerCase();
    if (normalized == 'all') return LoopMode.all;
    if (normalized == 'off') return LoopMode.off;
    return LoopMode.one;
  }

  void _syncPositionToPlaybackState(Duration position) {
    final int currentQueueIndex =
        _audioPlayer.currentIndex ?? playbackState.value.queueIndex ?? 0;
    playbackState.add(
      playbackState.value.copyWith(
        queueIndex: currentQueueIndex,
        updatePosition: position,
        repeatMode: _repeatModeFromLoopMode(_audioPlayer.loopMode),
      ),
    );
  }

  Future<void> _recoverLoopOneOnCompletion() async {
    if (_isRestartingLoopOne || _isRestoringFromCache) return;
    if (queue.value.isEmpty) return;

    _isRestartingLoopOne = true;
    try {
      await _audioPlayer.seek(Duration.zero);
      _syncPositionToPlaybackState(Duration.zero);
      await _audioPlayer.play();
      unawaited(_persistPlaybackState(force: true));
    } catch (_) {
      // Ignore loop recovery failure to avoid breaking playback thread.
    } finally {
      _isRestartingLoopOne = false;
    }
  }

  /// 从mediaItem或playbackState.queueIndex解析当前目标播放 index
  /// 优先使用mediaItem.id在队列中的位置，其次playbackState.queueIndex
  /// 两者均不可用时回退到0
  int _resolveTargetIndex(List<MediaItem> currentQueue) {
    final String? currentMediaId = mediaItem.value?.id;
    if (currentMediaId != null && currentMediaId.isNotEmpty) {
      final int hit = currentQueue.indexWhere(
        (MediaItem item) => item.id == currentMediaId,
      );
      if (hit >= 0) return hit;
    }
    final int? queueIndex = playbackState.value.queueIndex;
    if (queueIndex != null && queueIndex >= 0 && queueIndex < currentQueue.length) {
      return queueIndex;
    }
    return 0;
  }

  /// 仅在播放器处于idle时执行：用逻辑状态（mediaItem/playbackState.queueIndex）
  /// 对齐底层播放器，并在必要时恢复播放位置
  /// 适用场景：preload=false后首次播放、意外idle后恢复
  Future<void> _restorePlayerIfIdle() async {
    if (_audioPlayer.playerState.processingState != ProcessingState.idle) return;
    final List<MediaItem> currentQueue = queue.value;
    if (currentQueue.isEmpty) return;

    final int targetIndex = _resolveTargetIndex(currentQueue);
    final int? playerIndexBefore = _audioPlayer.currentIndex;
    final Duration positionBefore = _audioPlayer.position;
    // 仅当index未变且有有效进度时才恢复到原位置（意外idle场景）
    // 正常启动/切歌均从头开始
    final bool keepPosition = playerIndexBefore == targetIndex
        && positionBefore > Duration.zero;

    _isPreparingPlay = true;
    _preparingPlayTargetIndex = targetIndex;
    try {
      await _audioPlayer.load();
    } catch (_) {
      // 预加载失败，清除标志，回退到直接 play()
      _isPreparingPlay = false;
      _preparingPlayTargetIndex = null;
      return;
    }
    // load()后保险seek：media_kit with preload=false不一定正确应用
    // initialIndex/initialPosition，显式seek确保位置对齐
    final Duration seekTarget = keepPosition ? positionBefore : Duration.zero;
    await _audioPlayer.seek(seekTarget, index: targetIndex);
    _syncPositionToPlaybackState(seekTarget);
  }

  /// 跳过灰色歌曲
  Future<bool> _handleGreyStartIfNeeded() async {
    if (_isHandlingGreyStart) return true;
    final index = _audioPlayer.currentIndex;
    if (index == null || index < 0) return true;
    // 同一首歌按索引只检查一次
    if (_lastPlayStartCheckedIndex == index) return true;
    _lastPlayStartCheckedIndex = index;
    final currentQueue = queue.value;
    if (index >= currentQueue.length) return true;
    final extras = currentQueue[index].extras;
    final isGrey = extras != null && extras['isGrey'] == true;
    if (!isGrey) return true;
    _isHandlingGreyStart = true;
    try {
      final hasNext = index < currentQueue.length - 1;
      if (hasNext) {
        // 命中灰色歌曲，直接跳下一首
        await skipToNext();
        return true;
      }
      // 尾端也是灰色歌曲，停止播放
      await stop();
      return false;
    } finally {
      _isHandlingGreyStart = false;
    }
  }
}
