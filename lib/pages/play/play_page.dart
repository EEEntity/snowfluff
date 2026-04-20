import 'dart:async';
import 'package:snowfluff/common/music_handler.dart';
import 'package:snowfluff/pages/play/provider.dart';
import 'package:snowfluff/pages/provider.dart';
import 'package:snowfluff/router/app_router.dart';
import 'package:snowfluff/router/router.dart';
import 'package:snowfluff/utils/device_config.dart';
import 'package:snowfluff/widgets/album_view.dart';
import 'package:snowfluff/widgets/lyric_view.dart';
import 'package:snowfluff/widgets/play_background.dart';
import 'package:snowfluff/widgets/play_header.dart';
import 'package:snowfluff/widgets/play_progress.dart';
import 'package:snowfluff/widgets/playback_controls.dart';
import 'package:snowfluff/widgets/song_info_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:audio_service/audio_service.dart';

class PlayPage extends ConsumerStatefulWidget {
  final ScrollController? scrollController;
  const PlayPage({
    super.key,
    this.scrollController,
  });

  @override
  ConsumerState<PlayPage> createState() => _PlayPageState();
}

class _PlayPageState extends ConsumerState<PlayPage> {
  bool _showHeavyContent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _showHeavyContent = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return switch(DeviceConfig.layoutMode) {
      LayoutMode.desktop => _DesktopWidePlayPage(
          scrollController: widget.scrollController,
          enableHeavyContent: _showHeavyContent,
        ),
      LayoutMode.tablet => _TabletPlayPage(
          enableHeavyContent: _showHeavyContent,
        ),
      LayoutMode.mobile => _MobilePlayPage(
          enableHeavyContent: _showHeavyContent,
        ),
    };
  }
}

mixin _HasLyricsLayoutMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool _hasLyrics = false;
  ProviderSubscription<int>? _songIdSubscription;
  ProviderSubscription<AsyncValue<List<LyricLine>>>? _lyricSubscription;

  bool get hasLyricsValue => _hasLyrics;

  void initHasLyricsListener() {
    // 背景预取_LyricPrefetcher保证provider在页面打开前已有数据
    // 第一帧直接渲染正确布局，不触发AnimatedAlign
    final initialSongId = ref.read(
      mediaItemProvider.select((s) => int.tryParse(s.value?.id ?? '') ?? 0),
    );
    if (initialSongId > 0) {
      ref.read(mediaLyricProvider(initialSongId)).whenData((lyrics) {
        _hasLyrics = lyrics.isNotEmpty;
      });
    }
    // 只监听页面内切歌
    _songIdSubscription = ref.listenManual<int>(
      mediaItemProvider.select((s) => int.tryParse(s.value?.id ?? '') ?? 0),
      (previous, songId) {
        _lyricSubscription?.close();
        if (songId <= 0) {
          _setHasLyrics(false);
          return;
        }
        _lyricSubscription = ref.listenManual<AsyncValue<List<LyricLine>>>(
          mediaLyricProvider(songId),
          (_, next) => next.whenData((lyrics) => _setHasLyrics(lyrics.isNotEmpty)),
          fireImmediately: true,
        );
      },
      fireImmediately: false,
    );
  }

  void _setHasLyrics(bool value) {
    if (value == _hasLyrics) return;
    if (!mounted) {
      _hasLyrics = value;
      return;
    }
    setState(() {
      _hasLyrics = value;
    });
  }

  void disposeHasLyricsListener() {
    _lyricSubscription?.close();
    _songIdSubscription?.close();
  }
}

class _DesktopWidePlayPage extends ConsumerStatefulWidget {
  // 也许可以移除scrollController，因为桌面端全屏模式下通常不需要整体滚动
  final ScrollController? scrollController;
  final bool enableHeavyContent;
  const _DesktopWidePlayPage({
    this.scrollController,
    this.enableHeavyContent = true,
  });

  @override
  ConsumerState<_DesktopWidePlayPage> createState() => _DesktopWidePlayPageState();
}

class _DesktopWidePlayPageState extends ConsumerState<_DesktopWidePlayPage>
    with _HasLyricsLayoutMixin<_DesktopWidePlayPage> {
  static const Duration _kPaneShiftDuration = Duration(milliseconds: 500);
  static const Curve _kPaneShiftCurve = Curves.ease;
  static const Curve _kLyricsFadeInCurve = Interval(0.62, 1.0, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    initHasLyricsListener();
  }

  @override
  void dispose() {
    disposeHasLyricsListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final songId = ref.watch(mediaItemProvider.select((s) => int.tryParse(s.value?.id ?? '') ?? 0));
    final hasLyrics = hasLyricsValue;
    return Scaffold(
      body: Stack(
        children: [
          const PlayBackground(),
          const PlayHeader(),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      AnimatedAlign(
                        duration: _kPaneShiftDuration,
                        curve: _kPaneShiftCurve,
                        alignment: hasLyrics ? const Alignment(-1, 0) : Alignment.center,
                        child: FractionallySizedBox(
                          widthFactor: 5 / 11,
                          heightFactor: 1,
                          // 左栏
                          child: AnimatedContainer(
                            duration: _kPaneShiftDuration,
                            curve: _kPaneShiftCurve,
                            // 使用Padding实现稍微偏右(靠近中线)
                            // 左边留白多一些，右边(中线)留白少一些
                            padding: EdgeInsets.only(
                              left: hasLyrics ? 0.08.sw : 0.00.sw,
                              right: 0.00.sw,
                            ),
                            // 用LayoutBuilder获取左栏的实际可用尺寸
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                // 获取父容器(左栏)的可用的最大高度
                                final double maxAvailableHeight = constraints.maxHeight;
                                // "安全"的内容高度，比如占可用高度的85%，防止贴边
                                final double contentHeight = maxAvailableHeight * 0.85;
                                // 用Center让内容垂直居中
                                return Center(
                                  child: SizedBox(
                                    // 限制内容的最高高度
                                    height: contentHeight,
                                    // CrossAxisAlignment.end内容水平居中对齐
                                    // Column外部水平方向靠右
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center, // Column 内部垂直居中
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        // 封面AlbumView
                                        Flexible(
                                          flex: 4, // 封面占主要高度
                                          child: FractionallySizedBox(
                                            widthFactor: 0.8, // 宽度占左栏宽度的80%
                                            // heightFactor: 1.0, // 自动适配
                                            child: Consumer(
                                              builder: (context, ref, child) {
                                                final artUrl = ref.watch(mediaItemProvider.select((s) => s.value?.artUri.toString()));
                                                return AlbumView(
                                                  imageUrl: artUrl,
                                                );
                                              },
                                            )
                                          ),
                                        ),
                                        // 动态间距
                                        SizedBox(height: contentHeight * 0.05),
                                        // 歌曲信息
                                        Consumer(
                                          builder: (context, ref, child) {
                                            final title = ref.watch(mediaItemProvider.select((s) => s.value?.title ?? "未知歌曲"));
                                            final media = ref.watch(mediaItemProvider).value;
                                            final artists = _extractArtistsFromMedia(media)
                                                .map((a) => ArtistInfo(id: a.id, name: a.name))
                                                .toList(growable: false);
                                            return SongInfoHeaderExtended(
                                              title: title,
                                              artists: artists,
                                            );
                                          },
                                        ),
                                        SizedBox(height: contentHeight * 0.03),
                                        // 进度条
                                        FractionallySizedBox(
                                          widthFactor: 0.9, // 进度条宽一些
                                          child: Consumer(
                                            builder: (context, ref, child) {
                                              final positionMs = ref.watch(playbackStateProvider.select((s) => s.value?.updatePosition.inMilliseconds ?? 0));
                                              final durationMs = ref.watch(mediaItemProvider.select((s) => s.value?.duration?.inMilliseconds ?? 0));
                                              return MusicProgressBar(
                                                positionMs: positionMs,
                                                durationMs: durationMs,
                                                onChangeEnd: (val) {
                                                  final seekTo = Duration(milliseconds: (durationMs * val).toInt());
                                                  SnowfluffMusicHandler().seek(seekTo);
                                                },
                                              );
                                            },
                                          ),
                                        ),
                                        SizedBox(height: contentHeight * 0.05),
                                        // 控制栏
                                        const PlaybackControlBar(),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: _kPaneShiftDuration,
                        reverseDuration: Duration.zero,
                        switchInCurve: _kLyricsFadeInCurve,
                        switchOutCurve: Curves.easeOutCubic,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(opacity: animation, child: child);
                        },
                        child: hasLyrics
                            ? Align(
                                key: const ValueKey('desktop-lyrics-pane'),
                                alignment: Alignment.centerRight,
                                child: FractionallySizedBox(
                                  widthFactor: 6 / 11,
                                  heightFactor: 1,
                                  child: Container(
                                    // 左右留少量边界(sw百分比)
                                    padding: EdgeInsets.symmetric(horizontal: 0.04.sw),
                                    child: ScrollConfiguration(
                                      behavior: ScrollConfiguration.of(context).copyWith(
                                        scrollbars: false, // 桌面端去掉滚动条
                                      ),
                                      child: Consumer(
                                        builder: (context, ref, child) {
                                          if (!widget.enableHeavyContent) {
                                            return const SizedBox.shrink();
                                          }
                                          return LyricView(
                                            songId: songId,
                                            curLineIndex: 0,
                                            isTouchScreen: false,
                                            showTranslatedLyrics: true,
                                            textAlign: TextAlign.center,
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            fontSize: 28.0,
                                            onLyricTap: (time) {
                                              SnowfluffMusicHandler().seek(time);
                                            },
                                          );
                                        },
                                      )
                                    )
                                  ),
                                ),
                              )
                            : const SizedBox(key: ValueKey('desktop-lyrics-hidden')),
                      ),
                    ],
                  ),
                ),
                // 底部预留少量间距
                SizedBox(height: 10.h),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabletPlayPage extends ConsumerStatefulWidget {
  final bool enableHeavyContent;
  const _TabletPlayPage({this.enableHeavyContent = true});

  @override
  ConsumerState<_TabletPlayPage> createState() => _TabletPlayPageState();
}

class _TabletPlayPageState extends ConsumerState<_TabletPlayPage>
    with _HasLyricsLayoutMixin<_TabletPlayPage> {
  static const Duration _kPaneShiftDuration = Duration(milliseconds: 500);
  static const Curve _kPaneShiftCurve = Curves.ease;
  static const Curve _kLyricsFadeInCurve = Interval(0.62, 1.0, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    initHasLyricsListener();
  }

  @override
  void dispose() {
    disposeHasLyricsListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final songId = ref.watch(mediaItemProvider.select((s) => int.tryParse(s.value?.id ?? '') ?? 0));
    final hasLyrics = hasLyricsValue;
    return Scaffold(
      body: Stack(
        children: [
          const PlayBackground(), // 纯色背景
          const PlayHeader(), // 收起按钮
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      AnimatedAlign(
                        duration: _kPaneShiftDuration,
                        curve: _kPaneShiftCurve,
                        alignment: hasLyrics ? const Alignment(-1, 0) : Alignment.center,
                        child: FractionallySizedBox(
                          widthFactor: 5 / 11,
                          heightFactor: 1,
                          child: AnimatedContainer(
                            duration: _kPaneShiftDuration,
                            curve: _kPaneShiftCurve,
                            padding: EdgeInsets.only(
                              left: hasLyrics ? 0.02.sw : 0.00.sw,
                              right: 0.00.sw
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final double maxAvailableHeight = constraints.maxHeight;
                                final double contentHeight = maxAvailableHeight * 0.85;
                                return Center(
                                  child: SizedBox(
                                    height: contentHeight,
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Flexible(
                                          flex: 4,
                                          child: FractionallySizedBox(
                                            widthFactor: 0.8,
                                            child: Consumer(
                                              builder: (context, ref, child) {
                                                final artUrl = ref.watch(mediaItemProvider.select((s) => s.value?.artUri.toString()));
                                                return AlbumView(
                                                  imageUrl: artUrl,
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                        SizedBox(height: contentHeight * 0.05),
                                        Consumer(
                                          builder: (context, ref, child) {
                                            final title = ref.watch(mediaItemProvider.select((s) => s.value?.title ?? '未知歌曲'));
                                            final media = ref.watch(mediaItemProvider).value;
                                            final artists = _extractArtistsFromMedia(media)
                                                .map((a) => ArtistInfo(id: a.id, name: a.name))
                                                .toList(growable: false);
                                            return SongInfoHeaderExtended(
                                              title: title,
                                              artists: artists,
                                            );
                                          },
                                        ),
                                        SizedBox(height: contentHeight * 0.03),
                                        FractionallySizedBox(
                                          widthFactor: 0.9, // 进度条宽度
                                          child: RepaintBoundary(
                                            child: Consumer(
                                              builder: (context, ref, child) {
                                                final positonMs = ref.watch(playbackStateProvider.select((s) => s.value?.updatePosition.inMilliseconds ?? 0));
                                                final durationMs = ref.watch(mediaItemProvider.select((s) => s.value?.duration?.inMilliseconds ?? 0));
                                                return MusicProgressBar(
                                                  positionMs: positonMs,
                                                  durationMs: durationMs,
                                                  onChangeEnd: (val) {
                                                    final seekTo = Duration(milliseconds: (durationMs * val).toInt());
                                                    SnowfluffMusicHandler().seek(seekTo);
                                                  },
                                                );
                                              },
                                            ),
                                          )
                                        ),
                                        SizedBox(height: contentHeight * 0.05),
                                        const PlaybackControlBar(), // 可能要优化这里的Raster frame消耗
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: _kPaneShiftDuration,
                        reverseDuration: Duration.zero,
                        switchInCurve: _kLyricsFadeInCurve,
                        switchOutCurve: Curves.easeOutCubic,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(opacity: animation, child: child);
                        },
                        child: hasLyrics
                            ? Align(
                                key: const ValueKey('tablet-lyrics-pane'),
                                alignment: Alignment.centerRight,
                                child: FractionallySizedBox(
                                  widthFactor: 6 / 11,
                                  heightFactor: 1,
                                  child: RepaintBoundary(
                                    child: Container(
                                      padding: EdgeInsets.symmetric(horizontal: 0.02.sw),
                                      child: ScrollConfiguration(
                                        behavior: ScrollConfiguration.of(context).copyWith(
                                          scrollbars: false,
                                        ),
                                        child: widget.enableHeavyContent
                                            ? LyricView(
                                                songId: songId,
                                                curLineIndex: 0,
                                                isTouchScreen: true,
                                                textAlign: TextAlign.center,
                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                fontSize: 28.0,
                                                onLyricTap: (time) {
                                                  SnowfluffMusicHandler().seek(time);
                                                },
                                              )
                                            : const SizedBox.shrink(),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox(key: ValueKey('tablet-lyrics-hidden')),
                      )
                    ],
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _MobilePlayPage extends ConsumerStatefulWidget {
  final bool enableHeavyContent;

  const _MobilePlayPage({this.enableHeavyContent = true});

  @override
  ConsumerState<_MobilePlayPage> createState() => _MobilePlayPageState();
}

class _MobilePlayPageState extends ConsumerState<_MobilePlayPage> {
  void _collapsePlayPage() {
    if (!mounted) return;
    if (ModalRoute.of(context)?.canPop ?? false) {
      Navigator.of(context).pop();
      return;
    }
    context.go(AppRouter.home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MobilePlayPanelCard(
        enableHeavyContent: widget.enableHeavyContent,
        onQuickCollapse: _collapsePlayPage,
      ),
    );
  }
}

class MobilePlayPanelCard extends ConsumerStatefulWidget {
  final bool enableHeavyContent;
  final VoidCallback? onQuickCollapse;
  final bool collapseOnArtistNavigate;

  const MobilePlayPanelCard({
    super.key,
    this.enableHeavyContent = true,
    this.onQuickCollapse,
    this.collapseOnArtistNavigate = false,
  });

  @override
  ConsumerState<MobilePlayPanelCard> createState() => _MobilePlayPanelCardState();
}

class _MobilePlayPanelCardState extends ConsumerState<MobilePlayPanelCard> {
  bool _showLyrics = false;

  Future<void> _openQueueAndCollapse() async {
    _handleQuickCollapse();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final shellContext = shellNavigatorKey.currentContext;
      if (shellContext == null) return;
      final path = GoRouter.of(shellContext).state.path;
      if (path != AppRouter.playqueue) {
        shellContext.push(AppRouter.playqueue);
      }
    });
  }

  void _switchToLyrics() {
    if (_showLyrics) return;
    setState(() {
      _showLyrics = true;
    });
  }

  void _switchToCover() {
    if (!_showLyrics) return;
    setState(() {
      _showLyrics = false;
    });
  }

  void _handleQuickCollapse() {
    if (widget.onQuickCollapse != null) {
      widget.onQuickCollapse!.call();
      return;
    }
    if (ModalRoute.of(context)?.canPop ?? false) {
      Navigator.of(context).pop();
      return;
    }
    context.go(AppRouter.home);
  }

  Future<void> _showArtistsDialog(MediaItem? media) async {
    final artists = _extractArtistsFromMedia(media);
    if (artists.isEmpty) return;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '歌手列表',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return SafeArea(
          child: Center(
            child: Material(
              color: Theme.of(dialogContext).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14.w),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 0.86.sw,
                  maxHeight: 0.62.sh,
                  minWidth: 260.w,
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(14.w, 14.w, 14.w, 10.w),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '歌手',
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 10.w),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: artists.length,
                          itemBuilder: (context, index) {
                            final artist = artists[index];
                            final canJump = artist.id != null && artist.id! > 0;
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 4.w),
                              title: Text(
                                artist.name,
                                style: TextStyle(fontSize: 14.sp),
                              ),
                              trailing: canJump
                                  ? Icon(Icons.chevron_right, size: 18.sp)
                                  : null,
                              onTap: canJump
                                  ? () {
                                      Navigator.of(dialogContext).pop();
                                      if (widget.collapseOnArtistNavigate) {
                                        widget.onQuickCollapse?.call();
                                      }
                                      context.go('${AppRouter.artist}?id=${artist.id}');
                                    }
                                  : null,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final songId = ref.watch(
      mediaItemProvider.select((s) => int.tryParse(s.value?.id ?? '') ?? 0),
    );

    return Stack(
      children: [
        const PlayBackground(),
        SafeArea(
          minimum: EdgeInsets.only(top: 6.w),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10.w),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _handleQuickCollapse,
                      icon: Icon(
                        Icons.expand_more_rounded,
                        size: 32.sp,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () =>
                          _showArtistsDialog(ref.read(mediaItemProvider).value),
                      icon: Icon(
                        Icons.person_rounded,
                        size: 22.sp,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _showLyrics
                      ? _MobileLyricPane(
                          key: const ValueKey('mobile-lyric-pane'),
                          songId: songId,
                          enableHeavyContent: widget.enableHeavyContent,
                          onToggleCover: _switchToCover,
                        )
                      : _MobileCoverPane(
                          key: const ValueKey('mobile-cover-pane'),
                          onToggleLyrics: _switchToLyrics,
                          onShowQueue: _openQueueAndCollapse,
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MobileCoverPane extends ConsumerWidget {
  final VoidCallback onToggleLyrics;
  final Future<void> Function()? onShowQueue;

  const _MobileCoverPane({
    super.key,
    required this.onToggleLyrics,
    this.onShowQueue,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onToggleLyrics,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final contentHeight = constraints.maxHeight * 0.92;
            final topSectionShift = contentHeight * 0.08;
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: contentHeight,
                child: Padding(
                  padding: EdgeInsets.only(top: contentHeight * 0.03),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        flex: 4,
                        child: Transform.translate(
                          offset: Offset(0, -topSectionShift),
                          child: FractionallySizedBox(
                            widthFactor: 0.80,
                            child: Consumer(
                              builder: (context, ref, child) {
                                final artUrl = ref.watch(
                                  mediaItemProvider.select(
                                    (s) => s.value?.artUri.toString(),
                                  ),
                                );
                                return _MobileSwipeAlbumCard(
                                  imageUrl: artUrl,
                                  onTap: onToggleLyrics,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: contentHeight * 0.03),
                      Transform.translate(
                        offset: Offset(0, -contentHeight * 0.12),
                        child: Consumer(
                          builder: (context, ref, child) {
                            final title = ref.watch(
                          mediaItemProvider.select((s) => s.value?.title ?? '未知歌曲'),
                            );
                            final artists = ref.watch(
                              mediaItemProvider.select(
                            (s) => s.value?.artist?.split(' / ') ?? const <String>[],
                              ),
                            );
                            return SongInfoHeader(title: title, artists: artists);
                          },
                        ),
                      ),
                      SizedBox(height: contentHeight * 0.03),
                      FractionallySizedBox(
                        widthFactor: 0.90,
                        child: Consumer(
                          builder: (context, ref, child) {
                            final positionMs = ref.watch(
                              playbackStateProvider.select(
                            (s) => s.value?.updatePosition.inMilliseconds ?? 0,
                              ),
                            );
                            final durationMs = ref.watch(
                              mediaItemProvider.select(
                                (s) => s.value?.duration?.inMilliseconds ?? 0,
                              ),
                            );
                            return MusicProgressBar(
                              positionMs: positionMs,
                              durationMs: durationMs,
                              onChangeEnd: (val) {
                                final seekTo = Duration(
                                  milliseconds: (durationMs * val).toInt(),
                                );
                                SnowfluffMusicHandler().seek(seekTo);
                              },
                            );
                          },
                        ),
                      ),
                      SizedBox(height: contentHeight * 0.04),
                      _MobilePlaybackControlBar(onShowQueue: onShowQueue),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MobileSwipeAlbumCard extends StatefulWidget {
  final String? imageUrl;
  final VoidCallback onTap;

  const _MobileSwipeAlbumCard({required this.imageUrl, required this.onTap});

  @override
  State<_MobileSwipeAlbumCard> createState() => _MobileSwipeAlbumCardState();
}

class _MobileSwipeAlbumCardState extends State<_MobileSwipeAlbumCard> {
  static const double _kMaxDragFraction = 0.28;
  static const double _kTriggerFraction = 0.22;
  static const double _kIncomingStartFraction = 0.18;
  static const Duration _kFadeDuration = Duration(milliseconds: 220);

  double _dragFraction = 0;
  double _incomingStartFraction = 0;
  double _incomingOpacity = 1;
  String? _outgoingImageUrl;
  double _outgoingFraction = 0;
  double _outgoingOpacity = 0;
  bool _awaitingTrackChange = false;
  Timer? _fallbackTimer;
  Timer? _clearOutgoingTimer;

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _clearOutgoingTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _MobileSwipeAlbumCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hasTrackChanged = oldWidget.imageUrl != widget.imageUrl;
    if (_awaitingTrackChange && hasTrackChanged) {
      _finishSwitchAnimation();
    }
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_awaitingTrackChange) return;
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 1;
    final deltaFraction = details.delta.dx / width;
    setState(() {
      _dragFraction = (_dragFraction + deltaFraction).clamp(
        -_kMaxDragFraction,
        _kMaxDragFraction,
      );
    });
  }

  void _onHorizontalDragCancel() {
    if (_awaitingTrackChange) return;
    setState(() {
      _dragFraction = 0;
    });
  }

  Future<void> _onHorizontalDragEnd() async {
    if (_awaitingTrackChange) return;
    if (_dragFraction.abs() < _kTriggerFraction) {
      setState(() {
        _dragFraction = 0;
      });
      return;
    }

    final switchToPrevious = _dragFraction > 0;
    final releasedFraction = _dragFraction;
    final outgoing = widget.imageUrl;

    setState(() {
      _dragFraction = 0;
      _incomingStartFraction = switchToPrevious
          ? -_kIncomingStartFraction
          : _kIncomingStartFraction;
      _incomingOpacity = 0;
      _awaitingTrackChange = true;
      _outgoingImageUrl = outgoing;
      _outgoingFraction = releasedFraction;
      _outgoingOpacity = 1;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _outgoingFraction = switchToPrevious ? 1.0 : -1.0;
        _outgoingOpacity = 0;
      });
    });

    if (switchToPrevious) {
      await SnowfluffMusicHandler().skipToPrevious();
    } else {
      await SnowfluffMusicHandler().skipToNext();
    }

    _fallbackTimer?.cancel();
    _fallbackTimer = Timer(const Duration(milliseconds: 380), () {
      if (!mounted || !_awaitingTrackChange) return;
      _finishSwitchAnimation();
    });
  }

  void _finishSwitchAnimation() {
    if (!mounted) return;
    _fallbackTimer?.cancel();
    _clearOutgoingTimer?.cancel();
    setState(() {
      _dragFraction = _incomingStartFraction;
      _incomingOpacity = 1;
      _awaitingTrackChange = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _dragFraction = 0;
      });
    });

    _clearOutgoingTimer = Timer(_kFadeDuration, () {
      if (!mounted) return;
      setState(() {
        _outgoingImageUrl = null;
        _outgoingFraction = 0;
        _outgoingOpacity = 0;
        _incomingStartFraction = 0;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final settleDuration = _dragFraction == 0
        ? const Duration(milliseconds: 180)
        : Duration.zero;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragCancel: _onHorizontalDragCancel,
      onHorizontalDragEnd: (_) {
        _onHorizontalDragEnd();
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_outgoingImageUrl != null)
            IgnorePointer(
              child: AnimatedOpacity(
                duration: _kFadeDuration,
                curve: Curves.easeOutCubic,
                opacity: _outgoingOpacity,
                child: AnimatedSlide(
                    duration: _kFadeDuration,
                    curve: Curves.easeOutCubic,
                  offset: Offset(_outgoingFraction, 0),
                  child: AlbumView(imageUrl: _outgoingImageUrl),
                ),
              ),
            ),
          AnimatedOpacity(
            duration: _awaitingTrackChange
                ? _kFadeDuration
                : const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            opacity: _incomingOpacity,
            child: AnimatedSlide(
              duration: settleDuration,
              curve: Curves.easeOutCubic,
              offset: Offset(_dragFraction, 0),
              child: AlbumView(imageUrl: widget.imageUrl),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobilePlaybackControlBar extends ConsumerWidget {
  final Future<void> Function()? onShowQueue;

  const _MobilePlaybackControlBar({this.onShowQueue});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFM = ref.watch(isFMModeProvider.select((s) => s.value ?? false));
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            onPressed: isFM
                ? null
                : () async {
                    if (onShowQueue != null) {
                      await onShowQueue!.call();
                      return;
                    }
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      final shellContext = shellNavigatorKey.currentContext;
                      if (shellContext == null) return;
                      final path = GoRouter.of(shellContext).state.path;
                      if (path != AppRouter.playqueue) {
                        shellContext.push(AppRouter.playqueue);
                      }
                    });
                  },
            icon: Icon(
              Icons.queue_music,
              size: 28.sp,
              color: isFM ? Colors.white24 : Colors.white70,
            ),
          ),
          IconButton(
            onPressed: isFM
                ? () => SnowfluffMusicHandler().personalFMTrash()
                : () => SnowfluffMusicHandler().skipToPrevious(),
            icon: Icon(
              isFM ? Icons.thumb_down_outlined : Icons.skip_previous_rounded,
              size: isFM ? 20.sp : 28.sp,
              color: Colors.white,
            ),
          ),
          const PlayPauseButton(),
          IconButton(
            onPressed: () => SnowfluffMusicHandler().skipToNext(),
            icon: Icon(
              Icons.skip_next_rounded,
              size: 28.sp,
              color: Colors.white,
            ),
          ),
          LoopModeButton(disabled: isFM),
        ],
      ),
    );
  }
}

class _MobileLyricPane extends StatelessWidget {
  final int songId;
  final bool enableHeavyContent;
  final VoidCallback onToggleCover;

  const _MobileLyricPane({
    super.key,
    required this.songId,
    required this.enableHeavyContent,
    required this.onToggleCover,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 0.02.sw),
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: enableHeavyContent
              ? LyricView(
                  songId: songId,
                  curLineIndex: 0,
                  isTouchScreen: true,
                  textAlign: TextAlign.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  fontSize: 26.0,
                  onLyricTap: (time) {
                    SnowfluffMusicHandler().seek(time);
                  },
                  onToggleCover: onToggleCover,
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _SongArtistMeta {
  final int? id;
  final String name;

  const _SongArtistMeta({required this.id, required this.name});
}

List<_SongArtistMeta> _extractArtistsFromMedia(MediaItem? media) {
  if (media == null) return const <_SongArtistMeta>[];
  final extras = media.extras;
  final List<int> parsedIds = <int>[];
  final dynamic idsRaw = extras?['artistIds'];
  if (idsRaw is List) {
    for (final item in idsRaw) {
      final id = int.tryParse(item.toString());
      if (id != null && id > 0) parsedIds.add(id);
    }
  }

  final names = (media.artist ?? '')
      .split(' / ')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);

  if (names.isEmpty) return const <_SongArtistMeta>[];

  return List<_SongArtistMeta>.generate(names.length, (index) {
    final id = index < parsedIds.length ? parsedIds[index] : null;
    return _SongArtistMeta(id: id, name: names[index]);
  }, growable: false);
}
