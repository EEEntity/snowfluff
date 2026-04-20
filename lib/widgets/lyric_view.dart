// 歌词组件

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:async';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:snowfluff/pages/play/provider.dart';
import 'package:snowfluff/pages/provider.dart';
import 'package:snowfluff/utils/device_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LyricView extends ConsumerStatefulWidget {
  final int songId;
  final int curLineIndex;
  final bool isTouchScreen; // 预留，根据是否触屏影响交互
  final bool showTranslatedLyrics;
  final TextAlign textAlign;
  final CrossAxisAlignment crossAxisAlignment;
  final double fontSize;
  final Function(Duration)? onLyricTap;
  final VoidCallback? onToggleCover; // 触屏点击歌词切换封面
  const LyricView({
    super.key,
    required this.songId,
    required this.curLineIndex,
    this.isTouchScreen = false,
    this.showTranslatedLyrics = true,
    this.textAlign = TextAlign.center,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.fontSize = 18.0,
    this.onLyricTap,
    this.onToggleCover,
  });
  @override
  ConsumerState<LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends ConsumerState<LyricView> {
  static const double _kScrollAlignment = 0.4;
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();
  // 状态变量
  List<LyricLine> _lyrics = [];
  bool _isLoading = true;
  int _activeIndex = 0; // 当前高亮行索引
  int _centralIndex = -1; // 手动滚动时，处于屏幕中心的行
  bool _isUserScrolling = false; // 是否正在手动Seeking
  Timer? _autoScrollTimer; // 2秒回弹计时器
  String? _errorMsg;
  ProviderSubscription<AsyncValue<List<LyricLine>>>? _lyricSubscription;
  ProviderSubscription<Duration>? _positionSubscription;
  Duration _latestPosition = Duration.zero;
  @override
  void initState() {
    super.initState();
    _activeIndex = widget.curLineIndex;
    _itemPositionsListener.itemPositions.addListener(_updateCentralIndex);
    _bindPlaybackPosition();
    _bindLyricProvider();
  }
  void _bindLyricProvider() {
    _lyricSubscription?.close();
    _lyricSubscription = ref.listenManual<AsyncValue<List<LyricLine>>>(mediaLyricProvider(widget.songId), (previous, next) {
      if (!mounted) return;
      next.when(
        loading: () {
          if (_isLoading && _errorMsg == null) return;
          setState(() {
            _isLoading = true;
            _errorMsg = null;
          });
        },
        error: (error, stack) {
          setState(() {
            _isLoading = false;
            _errorMsg = '获取歌词失败: $error';
            _lyrics = [];
            _activeIndex = -1;
          });
        },
        data: (lyrics) {
          final resolvedIndex = _findLineIndex(_latestPosition, source: lyrics);
          setState(() {
            _lyrics = lyrics;
            _isLoading = false;
            _errorMsg = null;
            _activeIndex = resolvedIndex;
          });
          // 歌词就绪后强制同步一次当前进度
          if (lyrics.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _syncLineByPosition(_latestPosition, forceScroll: true);
            });
          }
        },
      );
    },
    fireImmediately: true);
  }
  void _bindPlaybackPosition() {
    _positionSubscription?.close();
    _positionSubscription = ref.listenManual<Duration>(playbackStateProvider.select((async) => async.value?.updatePosition ?? Duration.zero), (previous, next) {
      if (!mounted) return;
      final playingSongId = int.tryParse(ref.read(mediaItemProvider).value?.id ?? '') ?? 0;
      if (playingSongId != widget.songId) return;
      _latestPosition = next;
      _syncLineByPosition(next);
    },
    fireImmediately: true);
  }
  void _updateCentralIndex() {
    if (!_isUserScrolling) return;
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    // 找到最近的一行
    const targetAlignment = _kScrollAlignment;
    final closest = positions.reduce((a, b) {
      final da = (a.itemLeadingEdge - targetAlignment).abs();
      final db = (b.itemLeadingEdge - targetAlignment).abs();
      return da <= db ? a : b;
    });
    if (_centralIndex != closest.index) {
      setState(() {
        _centralIndex = closest.index;
      });
    }
  }
  void _resetAutoScrollTimer() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _isUserScrolling) {
        setState(() {
          _isUserScrolling = false;
          _centralIndex = -1;
        });
        _scrollToCurrentLine();
      }
    });
  }
  @override
  void didUpdateWidget(LyricView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果歌曲变了，就重新获取
    if (oldWidget.songId != widget.songId) {
      _latestPosition = Duration.zero; // 切歌时重置进度，避免旧进度干扰新歌词的行号计算
      _activeIndex = widget.curLineIndex;
      _centralIndex = -1;
      _isUserScrolling = false;
      _bindLyricProvider();
      return;
    }
  }
  void _scrollToCurrentLine() {
    if (!_itemScrollController.isAttached || _lyrics.isEmpty || _activeIndex < 0) return;
    _itemScrollController.scrollTo(
      index: _activeIndex,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutExpo,
      alignment: _kScrollAlignment,
    );
  }
  void _syncLineByPosition(Duration position, {bool forceScroll = false}) {
    // 按进度同步行号
    if(_lyrics.isEmpty) return;
    final nextIndex = _findLineIndex(position);
    final bool indexChanged = nextIndex != _activeIndex;
    if (indexChanged) {
      setState(() {
        _activeIndex = nextIndex;
      });
    }
    if (_isUserScrolling) return; // 手动滚动中不自动跳转
    if (!indexChanged && !forceScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToCurrentLine();
    });
  }
  int _findLineIndex(Duration position, {List<LyricLine>? source}) {
    final lyrics = source ?? _lyrics;
    if (lyrics.isEmpty) return -1; // 没有歌词时的特殊处理
    const tolerance = Duration(milliseconds: 500); // 时间容差，解决点击跳转时偏移到上一行的问题
    final target = position + tolerance;
    int i = _activeIndex;
    if (i < 0 || i >= lyrics.length) i = 0;
    if (target < lyrics[i].time) {
      while (i > 0 && target < lyrics[i].time) {
        i--;
      }
      return i;
    }
    while (i + 1 < lyrics.length && target >= lyrics[i + 1].time) {
      i++;
    }
    return i;
  }
  void _seekToLine(LyricLine line) {
    _autoScrollTimer?.cancel();
    setState(() {
      _isUserScrolling = false;
      _centralIndex = -1;
    });
    widget.onLyricTap?.call(line.time);
    _latestPosition = line.time;
    _syncLineByPosition(
      line.time,
      forceScroll: true,
    );
  }
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white24)
      );
    }
    if (_errorMsg != null) {
      return Center(
        child: TextButton(
          onPressed: () {
            ref.invalidate(mediaLyricProvider(widget.songId));
          },
          child: Text(
            "点击重试: $_errorMsg",
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    if (_lyrics.isEmpty) {
      // 桌面/平板：歌词区域直接隐藏，布局由上层的hasLyrics负责
      // 手机：仍需占位，用"暂无歌词"让用户知道可以点击切回封面
      if (!DeviceConfig.isMobile) return const SizedBox.shrink();
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggleCover,
        child: Center(
          child: Text(
            "暂无歌词",
            style: TextStyle(
              color: Colors.white54,
              fontSize: widget.fontSize, // 与歌词字体一致
            ),
          ),
        ),
      );
    }
    final scrollList = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // 移动端
        if (notification is ScrollStartNotification && notification.dragDetails != null) {
          if (!_isUserScrolling) {
            setState(() => _isUserScrolling = true);
          }
          _autoScrollTimer?.cancel();
          return false;
        }
        // 桌面端/触控板
        if (notification is UserScrollNotification) {
          if (notification.direction == ScrollDirection.idle) {
            // 停下滚动，开始等待回弹
            if (_isUserScrolling) {
              _resetAutoScrollTimer();
            }
          } else {
            if (!_isUserScrolling) {
              setState(() => _isUserScrolling = true);
            }
            _autoScrollTimer?.cancel();
          }
          return false;
        }
        // 移动端手指抬起，开始等待回弹
        if (notification is ScrollEndNotification && _isUserScrolling) {
          _resetAutoScrollTimer();
        }
        return false;
      },
      child: ScrollablePositionedList.builder(
        itemCount: _lyrics.length,
        itemScrollController: _itemScrollController,
        itemPositionsListener: _itemPositionsListener,
        padding: EdgeInsets.symmetric(vertical: MediaQuery.of(context).size.height / 2),
        itemBuilder: (context, index) {
          final line = _lyrics[index];
          final bool isTargeted = widget.isTouchScreen && _isUserScrolling && index == _centralIndex;
          return LyricItem(
            key: ValueKey(line.time),
            line: line,
            isCurrentLine: index == _activeIndex,
            isTargeted: isTargeted,
            showTrans: widget.showTranslatedLyrics && (line.ttext?.isNotEmpty ?? false),
            fontSize: widget.fontSize,
            textAlign: widget.textAlign,
            crossAxisAlignment: widget.crossAxisAlignment,
            onTap: () {
              if (widget.isTouchScreen) {
                final bool seekByTargetTap = _isUserScrolling && index == _centralIndex;
                if (!seekByTargetTap) {
                  widget.onToggleCover?.call();
                  return;
                }
                _seekToLine(line);
                return;
              }
              // 桌面端：直接跳转
              _seekToLine(line);
            },
          );
        },
      ),
    );
    if (!widget.isTouchScreen) return scrollList;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.onToggleCover,
      child: scrollList,
    );
  }
  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _lyricSubscription?.close();
    _positionSubscription?.close();
    _itemPositionsListener.itemPositions.removeListener(_updateCentralIndex);
    super.dispose();
  }
}

class LyricItem extends StatelessWidget {
  final LyricLine line;
  final bool isCurrentLine;
  final bool isTargeted; // 是否对应瞄准线
  final bool showTrans;
  final double fontSize;
  final TextAlign textAlign;
  final CrossAxisAlignment crossAxisAlignment;
  final VoidCallback onTap;
  const LyricItem({
    super.key,
    required this.line,
    required this.isCurrentLine,
    this.isTargeted = false,
    required this.showTrans,
    required this.fontSize,
    required this.textAlign,
    required this.crossAxisAlignment,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final mainColor = isTargeted
      ? Colors.white
      : (isCurrentLine ? Colors.white : Colors.white24);
    final subColor = isTargeted
      ? Colors.white70
      : (isCurrentLine ? Colors.white70 : Colors.white10);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12), // 歌词到边缘的间隔
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: crossAxisAlignment,
          children: [
            Text(
              line.text,
              textAlign: textAlign,
              // maxLines: 1,
              softWrap: true,
              // overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: mainColor,
                fontSize: fontSize,
                fontWeight: FontWeight.normal,
              ),
            ),
            if (showTrans)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  line.ttext!,
                  textAlign: textAlign,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: subColor,
                    fontSize: fontSize - 2,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}