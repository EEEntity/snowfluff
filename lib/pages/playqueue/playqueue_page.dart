// 播放队列页面

import 'package:snowfluff/common/music_handler.dart';
import 'package:snowfluff/pages/provider.dart';
import 'package:snowfluff/utils/device_config.dart';
import 'package:snowfluff/widgets/loading_indicator.dart';
import 'package:snowfluff/widgets/media_item_widget.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

// 外部可持有的页面句柄：
// 进入页面后可直接调用 scrollToCurrent()，不依赖重建页面
class PlayQueuePageHandle {
  PlayQueuePageHandle._();
  static final PlayQueuePageHandle instance = PlayQueuePageHandle._();
  _DesktopPlayQueuePageState? _state;
  void _attach(_DesktopPlayQueuePageState state) {
    _state = state;
  }
  void _detach(_DesktopPlayQueuePageState state) {
    if (identical(_state, state)) {
      _state = null;
    }
  }
  bool get isAttached => _state != null;
  Future<void> scrollToCurrent({bool animated = true}) async {
    await _state?._scrollToCurrent(animated: animated, force: true);
  }
}

class PlayQueuePage extends ConsumerWidget {
  const PlayQueuePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (DeviceConfig.layoutMode) {
      case LayoutMode.mobile:
        return const _MobilePlayQueuePage();
      case LayoutMode.desktop:
      case LayoutMode.tablet:
        return const _DesktopPlayQueuePage();
    }
  }
}
class _DesktopPlayQueuePage extends ConsumerStatefulWidget {
  const _DesktopPlayQueuePage();

  @override
  ConsumerState<_DesktopPlayQueuePage> createState() =>
      _DesktopPlayQueuePageState();
}

class _DesktopPlayQueuePageState extends ConsumerState<_DesktopPlayQueuePage>
    with AutomaticKeepAliveClientMixin {
  final ItemScrollController _itemScrollController = ItemScrollController();
  int _lastScrolledIndex = -1;
  ProviderSubscription<int>? _queueIndexSub;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    PlayQueuePageHandle.instance._attach(this);
    _lastScrolledIndex = ref.read(currentQueueIndexProvider);
    // 仅监听queueIndex，避免position高频变化导致重建
    _queueIndexSub = ref.listenManual<int>(
      currentQueueIndexProvider,
      (previous, next) {
        if (!mounted) return;
        if (next < 0) return;
        _scrollToCurrent(animated: true);
      }
    );
  }
  @override
  void dispose() {
    _queueIndexSub?.close();
    PlayQueuePageHandle.instance._detach(this);
    super.dispose();
  }
  Future<void> _scrollToCurrent({
    bool animated = true,
    bool force = false,
  }) async {
    final int currentIndex = ref.read(currentQueueIndexProvider);
    final int total = ref.read(queueLengthProvider);
    if (currentIndex < 0 || currentIndex >= total) return;
    if (!force && currentIndex == _lastScrolledIndex) return;
    if (!_itemScrollController.isAttached) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToCurrent(animated: animated, force: force);
      });
      return;
    }
    final double alignment = _alignmentForIndex(currentIndex, total);
    final int targetIndex = currentIndex + 1;
    _lastScrolledIndex = currentIndex;
    if (animated) {
      await _itemScrollController.scrollTo(
        index: targetIndex,
        alignment: alignment,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } else {
      _itemScrollController.jumpTo(
        index: targetIndex,
        alignment: alignment,
      );
    }
  }
  // 中间区域偏居中；首尾尽量贴边，避免大块空白
  double _alignmentForIndex(int index, int total) {
    if (total <= 1) return 0.0;
    if (index <= 1) return 0.0;
    return 0.45;
  }
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final queueAsync = ref.watch(mediaListProvider);
    return queueAsync.when(
      loading: () => const Center(child: LoadingIndicator()),
      error: (e, s) => Center(child: Text('播放队列加载失败: $e')),
      data: (medias) {
        final int currentIndex = ref.read(currentQueueIndexProvider);
        final bool hasValidCurrent = currentIndex >= 0 && currentIndex < medias.length;
        final int initialScrollIndex = hasValidCurrent ? currentIndex + 1 : 0;
        final double initialAlignment = hasValidCurrent
            ? _alignmentForIndex(currentIndex, medias.length)
            : 0.0;
        return ScrollablePositionedList.builder(
          padding: EdgeInsets.symmetric(horizontal: 60.w, vertical: 20.w),
          initialScrollIndex: initialScrollIndex,
          initialAlignment: initialAlignment,
          itemCount: medias.length + 1,
          itemScrollController: _itemScrollController,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: EdgeInsets.only(bottom: 14.w),
                child: _QueueHeader(count: medias.length),
              );
            }
            final mediaIndex = index - 1;
            final media = medias[mediaIndex];
            return _QueueItem(
              index: mediaIndex,
              media: media,
            );
          },
        );
      },
    );
  }
}

class _MobilePlayQueuePage extends ConsumerStatefulWidget {
  const _MobilePlayQueuePage();

  @override
  ConsumerState<_MobilePlayQueuePage> createState() =>
      _MobilePlayQueuePageState();
}

class _MobilePlayQueuePageState extends ConsumerState<_MobilePlayQueuePage>
    with AutomaticKeepAliveClientMixin {
  final ItemScrollController _itemScrollController = ItemScrollController();
  ProviderSubscription<int>? _queueIndexSub;
  int _lastScrolledIndex = -1;
  static const double _rowExtent = 58.0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _lastScrolledIndex = ref.read(currentQueueIndexProvider);
    _queueIndexSub = ref.listenManual<int>(currentQueueIndexProvider, (
      previous,
      next,
    ) {
      if (!mounted) return;
      if (next < 0) return;
      _scrollToCurrent(animated: true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToCurrent(animated: false, force: true);
    });
  }

  @override
  void dispose() {
    _queueIndexSub?.close();
    super.dispose();
  }

  Future<void> _scrollToCurrent({
    bool animated = true,
    bool force = false,
  }) async {
    final int currentIndex = ref.read(currentQueueIndexProvider);
    final int total = ref.read(queueLengthProvider);
    if (currentIndex < 0 || currentIndex >= total) return;
    if (!force && currentIndex == _lastScrolledIndex) return;
    if (!_itemScrollController.isAttached) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToCurrent(animated: animated, force: force);
      });
      return;
    }
    _lastScrolledIndex = currentIndex;
    final int targetIndex = currentIndex + 1;
    final double alignment = _alignmentForIndex(currentIndex, total);
    if (animated) {
      await _itemScrollController.scrollTo(
        index: targetIndex,
        alignment: alignment,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    _itemScrollController.jumpTo(index: targetIndex, alignment: alignment);
  }

  double _alignmentForIndex(int index, int total) {
    if (total <= 1) return 0.0;
    if (index <= 1) return 0.0;
    return 0.35;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final queueAsync = ref.watch(mediaListProvider);
    return queueAsync.when(
      loading: () => const Center(child: LoadingIndicator()),
      error: (e, s) => Center(child: Text('播放队列加载失败: $e')),
      data: (medias) {
        final int currentIndex = ref.read(currentQueueIndexProvider);
        final bool hasValidCurrent =
            currentIndex >= 0 && currentIndex < medias.length;
        final int initialScrollIndex = hasValidCurrent ? currentIndex + 1 : 0;
        final double initialAlignment = hasValidCurrent
            ? _alignmentForIndex(currentIndex, medias.length)
            : 0.0;
        final int itemCount = medias.isEmpty ? 2 : medias.length + 1;

        return ScrollablePositionedList.builder(
          padding: EdgeInsets.fromLTRB(14.w, 8.w, 14.w, 12.w),
          initialScrollIndex: initialScrollIndex,
          initialAlignment: initialAlignment,
          itemCount: itemCount,
          itemScrollController: _itemScrollController,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: EdgeInsets.only(bottom: 10.w),
                child: _MobileQueueHeader(count: medias.length),
              );
            }
            if (medias.isEmpty) {
              return Text(
                '暂无播放队列数据',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Theme.of(context).hintColor,
                ),
              );
            }
            final mediaIndex = index - 1;
            final media = medias[mediaIndex];
            final isGrey = media.extras?['isGrey'] == true;
            return SizedBox(
              height: _rowExtent.w,
              child: _MobileQueueItem(
                index: mediaIndex,
                media: media,
                isGrey: isGrey,
              ),
            );
          },
        );
      },
    );
  }
}

final currentQueueIndexProvider = Provider<int>((ref) {
  return ref.watch(
    playbackStateProvider.select((s) => s.value?.queueIndex ?? -1),
  );
});
final queueLengthProvider = Provider<int>((ref) {
  return ref.watch(
    mediaListProvider.select((s) => s.value?.length ?? 0),
  );
});
class _QueueHeader extends ConsumerWidget {
  final int count;
  const _QueueHeader({
    required this.count,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shuffleEnabled = ref.watch(
      playbackStateProvider.select(
        (s) => s.value?.shuffleMode == AudioServiceShuffleMode.all,
      ),
    );
    final loopMode = ref.watch(loopModeProvider);
    final modeText = shuffleEnabled ? '随机播放' : _loopModeText(loopMode);
    return Text(
      '播放队列 - $modeText（$count）',
      style: TextStyle(
        fontSize: 24.sp,
        fontWeight: FontWeight.bold,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _loopModeText(AudioServiceRepeatMode mode) {
    switch (mode) {
      case AudioServiceRepeatMode.one:
        return '单曲循环';
      case AudioServiceRepeatMode.all:
        return '列表循环';
      case AudioServiceRepeatMode.none:
        return '顺序播放';
      case AudioServiceRepeatMode.group:
        return '分组循环';
    }
  }
}

class _MobileQueueHeader extends ConsumerWidget {
  final int count;

  const _MobileQueueHeader({required this.count});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shuffleEnabled = ref.watch(
      playbackStateProvider.select(
        (s) => s.value?.shuffleMode == AudioServiceShuffleMode.all,
      ),
    );
    final loopMode = ref.watch(loopModeProvider);
    final modeText = shuffleEnabled ? '随机播放' : _loopModeText(loopMode);
    return Text(
      '播放队列-$modeText ($count)',
      style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _loopModeText(AudioServiceRepeatMode mode) {
    switch (mode) {
      case AudioServiceRepeatMode.one:
        return '单曲循环';
      case AudioServiceRepeatMode.all:
        return '列表循环';
      case AudioServiceRepeatMode.none:
        return '顺序播放';
      case AudioServiceRepeatMode.group:
        return '分组循环';
    }
  }
}

class _QueueItem extends ConsumerWidget {
  final int index;
  final MediaItem media;

  const _QueueItem({
    required this.index,
    required this.media,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isActive = ref.watch(
      currentQueueIndexProvider.select((current) => current == index),
    );
    final bool isGrey = media.extras?['isGrey'] == true;

    return Padding(
      padding: EdgeInsets.only(bottom: 8.w),
      child: MediaItemWidget(
        mediaItem: media,
        isGrey: isGrey,
        isActive: isActive,
        onTap: isGrey
            ? null
            : () => SnowfluffMusicHandler().skipToQueueIndex(index),
      ),
    );
  }
}

class _MobileQueueItem extends ConsumerWidget {
  final int index;
  final MediaItem media;
  final bool isGrey;

  const _MobileQueueItem({
    required this.index,
    required this.media,
    required this.isGrey,
  });

  Color _resolveActiveColor(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Color.alphaBlend(
      theme.colorScheme.primary.withValues(alpha: isDark ? 0.28 : 0.14),
      theme.colorScheme.surface,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isActive = ref.watch(
      currentQueueIndexProvider.select((current) => current == index),
    );
    final theme = Theme.of(context);
    final disabledColor = theme.disabledColor;
    final subColor = theme.hintColor;
    final radius = BorderRadius.circular(10.w);
    final effectiveActive = isActive && !isGrey;

    return Material(
      type: MaterialType.transparency,
      shape: RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          color: effectiveActive
              ? _resolveActiveColor(theme)
              : Colors.transparent,
          borderRadius: radius,
        ),
        child: InkWell(
          onTap: isGrey
              ? null
              : () => SnowfluffMusicHandler().skipToQueueIndex(index),
          borderRadius: radius,
          child: Row(
            children: [
              SizedBox(
                width: 28.w,
                child: Text(
                  (index + 1).toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: isGrey ? disabledColor : subColor,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      media.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: isGrey ? disabledColor : null,
                      ),
                    ),
                    SizedBox(height: 1.w),
                    Text(
                      _normalizedArtist(media.artist),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: isGrey ? disabledColor : subColor,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                _formatMobileQueueDuration(media.duration ?? Duration.zero),
                style: TextStyle(
                  fontSize: 11.sp,
                  color: isGrey ? disabledColor : subColor,
                ),
              ),
              SizedBox(width: 2.w),
            ],
          ),
        ),
      ),
    );
  }
}

String _normalizedArtist(String? artist) {
  final raw = (artist ?? '').trim();
  if (raw.isEmpty) return '未知歌手';
  final parts = raw
      .split(RegExp(r'\s*/\s*|、|，|,'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '未知歌手';
  return parts.join(' / ');
}

String _formatMobileQueueDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
