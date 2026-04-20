// 艺人页面

import 'package:snowfluff/common/music_handler.dart';
import 'package:snowfluff/pages/artist/provider.dart';
import 'package:snowfluff/pages/provider.dart';
import 'package:snowfluff/router/app_router.dart';
import 'package:snowfluff/utils/device_config.dart';
import 'package:snowfluff/widgets/cached_image.dart';
import 'package:snowfluff/widgets/loading_indicator.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

class ArtistPage extends ConsumerWidget {
  final int id;
  const ArtistPage(this.id, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoAsync = ref.watch(artistInfoProvider(id));
    final topMediasAsync = ref.watch(artistTopMediasProvider(id));
    final albumCardsAsync = ref.watch(artistAlbumCardsProvider(id));

    if (infoAsync.isLoading || topMediasAsync.isLoading || albumCardsAsync.isLoading) {
      return const Center(child: LoadingIndicator());
    }
    if (infoAsync.hasError || topMediasAsync.hasError || albumCardsAsync.hasError) {
      return const Center(child: Text('Something artist wrong...'));
    }

    final artistInfo = infoAsync.requireValue;
    final topMedias = topMediasAsync.requireValue;
    final albumCards = albumCardsAsync.requireValue;

    return switch (DeviceConfig.layoutMode) {
      LayoutMode.desktop => DesktopArtistPage(
        artistInfo: artistInfo,
        topMedias: topMedias,
        albumCards: albumCards,
      ),
      LayoutMode.tablet => TabletArtistPage(
        artistInfo: artistInfo,
        topMedias: topMedias,
        albumCards: albumCards,
      ),
      LayoutMode.mobile => MobileArtistPage(
        artistInfo: artistInfo,
        topMedias: topMedias,
        albumCards: albumCards,
      ),
    };
  }
}

class DesktopArtistPage extends ConsumerStatefulWidget {
  final ArtistInfoData artistInfo;
  final List<MediaItem> topMedias;
  final List<ArtistAlbumCardData> albumCards;

  static const double _rowExtent = 68.0;

  const DesktopArtistPage({
    super.key,
    required this.artistInfo,
    required this.topMedias,
    required this.albumCards,
  });

  @override
  ConsumerState<DesktopArtistPage> createState() => _DesktopArtistPageState();
}

class _DesktopArtistPageState extends ConsumerState<DesktopArtistPage> {
  // 专辑网格懒加载：每批次加载条数
  static const int _albumBatchSize = 20;

  // 距离底部小于该值时触发下一批加载
  static const double _loadMoreTriggerExtent = 1000.0;

  late final ScrollController _scrollController;
  late List<MediaItem> _queueSnapshot;
  late List<MediaItem> _previewTop12;

  int _visibleAlbumCount = 0;
  bool _isAppendingAlbums = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _recomputeSongCaches(force: true);
    _resetAlbumLazyState(force: true);

    // 首帧后检查一次，避免首批数据不足一屏时无法继续加载
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureViewportFilled();
    });
  }

  @override
  void didUpdateWidget(covariant DesktopArtistPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.topMedias, widget.topMedias)) {
      _recomputeSongCaches(force: true);
    }

    if (!identical(oldWidget.albumCards, widget.albumCards) ||
        oldWidget.albumCards.length != widget.albumCards.length) {
      _resetAlbumLazyState(force: true);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureViewportFilled();
      });
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _recomputeSongCaches({required bool force}) {
    if (!force) return;
    _queueSnapshot = List<MediaItem>.unmodifiable(widget.topMedias);
    _previewTop12 = List<MediaItem>.unmodifiable(_queueSnapshot.take(12));
  }

  void _resetAlbumLazyState({required bool force}) {
    if (!force) return;
    final total = widget.albumCards.length;
    _visibleAlbumCount = total < _albumBatchSize ? total : _albumBatchSize;
  }

  bool get _hasMoreAlbums => _visibleAlbumCount < widget.albumCards.length;

  void _onScroll() {
    _tryAppendAlbumsIfNeeded();
  }

  void _tryAppendAlbumsIfNeeded() {
    if (!_hasMoreAlbums || _isAppendingAlbums || !_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter > _loadMoreTriggerExtent) return;
    _appendAlbumBatch();
  }

  void _appendAlbumBatch() {
    if (!_hasMoreAlbums || _isAppendingAlbums) return;
    _isAppendingAlbums = true;

    final next = (_visibleAlbumCount + _albumBatchSize).clamp(0, widget.albumCards.length);
    if (next != _visibleAlbumCount && mounted) {
      setState(() {
        _visibleAlbumCount = next;
      });
    }

    _isAppendingAlbums = false;

    // 新批次渲染后继续检查，保证大屏下也能自动补齐内容
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureViewportFilled();
    });
  }

  void _ensureViewportFilled() {
    if (!_scrollController.hasClients || !_hasMoreAlbums || _isAppendingAlbums) return;
    if (_scrollController.position.maxScrollExtent <= 0) {
      _appendAlbumBatch();
    } else {
      _tryAppendAlbumsIfNeeded();
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeMediaId = ref.watch(mediaItemProvider.select((s) => s.value?.id));
    final firstPlayableIndex = _firstPlayableIndex(_queueSnapshot);
    final canPlay = firstPlayableIndex >= 0;
    final hotSongCount = _previewTop12.length;

    return CustomScrollView(
      controller: _scrollController,
      cacheExtent: DesktopArtistPage._rowExtent * 8,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20.w, 20.w, 20.w, 0),
          sliver: SliverToBoxAdapter(
            child: _ArtistHeader(
              artistInfo: widget.artistInfo,
              onPlay: canPlay
                  ? () => SnowfluffMusicHandler().updateQueue(
                      _queueSnapshot,
                      index: firstPlayableIndex,
                      queueName: '${widget.artistInfo.name} 热门歌曲',
                    )
                  : null,
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 20.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          sliver: const SliverToBoxAdapter(child: _SectionTitle('热门歌曲')),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 10.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          sliver: _previewTop12.isEmpty
              ? SliverToBoxAdapter(
                  child: Text(
                    '暂无热门歌曲',
                  style: TextStyle(fontSize: 12.sp, color: Theme.of(context).hintColor),
                  ),
                )
              : SliverLayoutBuilder(
                  builder: (context, constraints) {
                    const crossAxisCount = 4;
                    final crossSpacing = 10.w;
                    final mainSpacing = 8.w;
                    const itemAspect = 3.4;
                final itemWidth = (constraints.crossAxisExtent - (crossAxisCount - 1) * crossSpacing) / crossAxisCount;
                    final itemHeight = itemWidth / itemAspect;
                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: crossSpacing,
                        mainAxisSpacing: mainSpacing,
                        mainAxisExtent: itemHeight,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final media = _previewTop12[index];
                          final isGrey = media.extras?['isGrey'] == true;
                          return _TopSongGridItem(
                            media: media,
                            isActive: media.id == activeMediaId,
                            onTap: isGrey
                                ? null
                                : () => SnowfluffMusicHandler().updateQueue(
                                    _queueSnapshot,
                                    index: index,
                                    queueName: '${widget.artistInfo.name} 热门歌曲',
                                  ),
                          );
                        },
                        childCount: hotSongCount,
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: true,
                      ),
                    );
                  },
            )
        ),
        SliverToBoxAdapter(child: SizedBox(height: 10.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          sliver: const SliverToBoxAdapter(child: _SectionTitle('专辑')),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 10.w)),

        if (widget.albumCards.isEmpty)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            sliver: SliverToBoxAdapter(
              child: Text(
                '暂无专辑',
                style: TextStyle(fontSize: 12.sp, color: Theme.of(context).hintColor),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                const crossAxisCount = 5;
                final crossSpacing = 18.w;
                final mainSpacing = 16.w;

                final tileWidth =
                    (constraints.crossAxisExtent - (crossAxisCount - 1) * crossSpacing) /
                    crossAxisCount;

                // 卡片总高 = 正方形封面 + 标题 + 日期 + 间距
                final tileHeight = tileWidth + 4.w + 18.w + 2.w + 14.w + 4.w;

                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: crossSpacing,
                    mainAxisSpacing: mainSpacing,
                    mainAxisExtent: tileHeight,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final albumCard = widget.albumCards[index];
                      return _AlbumGridCard(
                        album: albumCard,
                        onTap: () => context.push(AppRouter.album, extra: albumCard.id),
                      );
                    },
                    // 只构建可见批次，降低瞬时内存和构建开销
                    childCount: _visibleAlbumCount,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                  ),
                );
              },
            ),
          ),

        if (_hasMoreAlbums)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 10.w, bottom: 20.w),
              child: Center(
                child: SizedBox(
                  width: 20.w,
                  height: 20.w,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          )
        else
          SliverToBoxAdapter(child: SizedBox(height: 20.w)),
      ],
    );
  }
}

class _ArtistHeader extends StatelessWidget {
  final ArtistInfoData artistInfo;
  final VoidCallback? onPlay;

  const _ArtistHeader({
    required this.artistInfo,
    this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const totalFlex = 11; // 3:8
        final coverSide = (constraints.maxWidth - 36.w) * 3 / totalFlex;
        final desc = artistInfo.briefDesc.trim().isEmpty ? '暂无简介' : artistInfo.briefDesc.trim();

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: AspectRatio(
                aspectRatio: 1,
                child: CachedImage(
                  imageUrl: artistInfo.picUrl,
                  borderRadius: 12.w,
                  pWidth: 1024,
                  pHeight: 1024,
                ),
              ),
            ),
            SizedBox(width: 36.w),
            Expanded(
              flex: 8,
              child: SizedBox(
                height: coverSide,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 8.w),
                    Text(
                      artistInfo.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 32.sp, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 6.w),
                    Text(
                      '艺人',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                    SizedBox(height: 6.w),
                    Text(
                      '${artistInfo.musicSize}首歌 · ${artistInfo.albumSize}张专辑',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                    SizedBox(height: 12.w),
                    Expanded(
                      child: Text(
                        desc,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.sp,
                          height: 1.45,
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                    ),
                    SizedBox(height: 10.w),
                    ElevatedButton.icon(
                      onPressed: onPlay,
                      icon: Icon(Icons.play_arrow, size: 18.sp),
                      label: Text(
                        '播放',
                        style: TextStyle(fontSize: 15.sp),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 14.w),
                      ),
                    ),
                    SizedBox(height: 2.w),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700),
    );
  }
}

class _TopSongGridItem extends StatefulWidget {
  final MediaItem media;
  final bool isActive;
  final VoidCallback? onTap;

  const _TopSongGridItem({
    required this.media,
    required this.isActive,
    this.onTap,
  });

  @override
  State<_TopSongGridItem> createState() => _TopSongGridItemState();
}

class _TopSongGridItemState extends State<_TopSongGridItem> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    final isGrey = media.extras?['isGrey'] == true;
    final enabled = !isGrey && widget.onTap != null;
    final hintColor = Theme.of(context).hintColor;
    final disabledColor = Theme.of(context).disabledColor;
    final activeBg = Theme.of(context).colorScheme.primary.withValues(alpha: 0.14);
    final hoverBg = hintColor.withValues(alpha: 0.18);

    Widget cover = SizedBox(
      width: 42.w,
      height: 42.w,
      child: CachedImage(
        imageUrl: media.artUri?.toString() ?? '',
        borderRadius: 8.w,
        pWidth: 256,
        pHeight: 256,
      ),
    );

    if (isGrey) {
      cover = Opacity(
        opacity: 0.65,
        child: ColorFiltered(
          colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.saturation),
          child: cover,
        ),
      );
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10.w),
          onTap: enabled ? widget.onTap : null,
          child: Ink(
            decoration: BoxDecoration(
              color: widget.isActive
                  ? activeBg
                  : (hovered && enabled ? hoverBg : Colors.transparent),
              borderRadius: BorderRadius.circular(10.w),
            ),
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.w),
            child: Row(
              children: [
                RepaintBoundary(child: cover),
                SizedBox(width: 10.w),
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
                          fontSize: 13.sp,
                          color: isGrey ? disabledColor : null,
                          fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 2.w),
                      Text(
                        media.artist ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: isGrey ? disabledColor : hintColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AlbumGridCard extends StatefulWidget {
  final ArtistAlbumCardData album;
  final VoidCallback onTap;

  const _AlbumGridCard({
    required this.album,
    required this.onTap,
  });

  @override
  State<_AlbumGridCard> createState() => _AlbumGridCardState();
}

class _AlbumGridCardState extends State<_AlbumGridCard> {
  bool titleHovered = false;

  @override
  Widget build(BuildContext context) {
    final title = widget.album.name.isEmpty ? '未知专辑' : widget.album.name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10.w),
                child: RepaintBoundary(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: CachedImage(
                      imageUrl: widget.album.picUrl,
                      fit: BoxFit.cover,
                      pWidth: 512,
                      pHeight: 512,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: 4.w),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => titleHovered = true),
          onExit: (_) => setState(() => titleHovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                decoration: titleHovered ? TextDecoration.underline : TextDecoration.none,
                decorationThickness: 1.2,
              ),
            ),
          ),
        ),
        SizedBox(height: 2.w),
        Text(
          _formatPublishDateCn(widget.album.publishTime),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10.sp,
            color: Theme.of(context).hintColor,
          ),
        ),
        SizedBox(height: 4.w),
      ],
    );
  }
}

int _firstPlayableIndex(List<MediaItem> medias) {
  for (int i = 0; i < medias.length; i++) {
    if (medias[i].extras?['isGrey'] != true) return i;
  }
  return -1;
}

String _formatPublishDateCn(int timestampMs) {
  if (timestampMs <= 0) return '发布时间未知';
  final dtUtc8 = DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true)
      .add(const Duration(hours: 8));
  return '${dtUtc8.year}年${dtUtc8.month}月${dtUtc8.day}日';
}

// 手机分支
class MobileArtistPage extends ConsumerStatefulWidget {
  static const double _songRowExtent = 58.0;
  static const double _albumRowExtent = 76.0;

  final ArtistInfoData artistInfo;
  final List<MediaItem> topMedias;
  final List<ArtistAlbumCardData> albumCards;

  const MobileArtistPage({
    super.key,
    required this.artistInfo,
    required this.topMedias,
    required this.albumCards,
  });

  @override
  ConsumerState<MobileArtistPage> createState() => _MobileArtistPageState();
}

class _MobileArtistPageState extends ConsumerState<MobileArtistPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late List<MediaItem> _queueSnapshot;
  late List<_MobileArtistSongRow> _songRows;
  final Set<int> _activatedTabs = <int>{0};
  bool _tabGestureLocked = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabInteraction);
    _recomputeData(force: true);
  }

  @override
  void didUpdateWidget(covariant MobileArtistPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _recomputeData(force: !identical(oldWidget.topMedias, widget.topMedias));
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabInteraction);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabInteraction() {
    if (!mounted) return;

    final index = _tabController.index;
    final offset = _tabController.offset;

    final interacting =
        _tabController.indexIsChanging || offset.abs() > 0.0001;

    var needsSetState = false;
    if (_tabGestureLocked != interacting) {
      _tabGestureLocked = interacting;
      needsSetState = true;
    }

    final candidates = <int>{index};
    if (offset > 0.01) {
      candidates.add(index + 1);
    } else if (offset < -0.01) {
      candidates.add(index - 1);
    }
    if (_tabController.indexIsChanging) {
      candidates.add(_tabController.index);
    }

    for (final tab in candidates) {
      if (tab < 0 || tab >= _tabController.length) continue;
      if (_activatedTabs.add(tab)) {
        needsSetState = true;
      }
    }

    if (needsSetState) {
      setState(() {});
    }
  }

  void _recomputeData({required bool force}) {
    if (!force) return;
    _queueSnapshot = List<MediaItem>.unmodifiable(widget.topMedias);
    _songRows = List<_MobileArtistSongRow>.unmodifiable(
      List<_MobileArtistSongRow>.generate(_queueSnapshot.length, (i) {
        final media = _queueSnapshot[i];
        return _MobileArtistSongRow(
          index: i,
          media: media,
          isGrey: media.extras?['isGrey'] == true,
        );
      }, growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = 14.w;

    return Column(
      children: [
        SizedBox(height: 4.w),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontal),
          child: _MobileArtistTabBar(controller: _tabController),
        ),
        SizedBox(height: 8.w),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            dragStartBehavior: DragStartBehavior.down,
            physics: const _MobileArtistTabViewPhysics(
              parent: ClampingScrollPhysics(),
            ),
            children: [
              _DeferredMobileArtistTabBody(
                enabled: _activatedTabs.contains(0),
                pointerLocked: _tabGestureLocked,
                child: _MobileArtistDetailTab(
                  artistInfo: widget.artistInfo,
                  bottomPadding: 14.w,
                ),
              ),
              _DeferredMobileArtistTabBody(
                enabled: _activatedTabs.contains(1),
                pointerLocked: _tabGestureLocked,
                child: _MobileArtistSongTab(
                  rows: _songRows,
                  queueSnapshot: _queueSnapshot,
                  artistName: widget.artistInfo.name,
                  horizontal: horizontal,
                ),
              ),
              _DeferredMobileArtistTabBody(
                enabled: _activatedTabs.contains(2),
                pointerLocked: _tabGestureLocked,
                child: _MobileArtistAlbumTab(
                  albums: widget.albumCards,
                  horizontal: horizontal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeferredMobileArtistTabBody extends StatelessWidget {
  final bool enabled;
  final bool pointerLocked;
  final Widget child;

  const _DeferredMobileArtistTabBody({
    required this.enabled,
    required this.pointerLocked,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final body = enabled
        ? child
        : const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );

    return IgnorePointer(
      ignoring: pointerLocked,
      child: RepaintBoundary(
        child: body,
      ),
    );
  }
}

class _MobileArtistTabBar extends StatelessWidget {
  final TabController controller;

  const _MobileArtistTabBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TabBar(
      controller: controller,
      isScrollable: false,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.transparent,
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      labelColor: theme.colorScheme.primary,
      unselectedLabelColor: theme.hintColor,
      indicator: _MobileArtistTabIndicator(
        color: theme.colorScheme.primary,
        width: 16.w,
        height: 2.w,
        radius: 99.w,
      ),
      labelStyle: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w500),
      unselectedLabelStyle: TextStyle(
        fontSize: 15.sp,
        fontWeight: FontWeight.w500,
      ),
      tabs: const [
        Tab(text: '详情'),
        Tab(text: '歌曲'),
        Tab(text: '专辑'),
      ],
    );
  }
}

class _MobileArtistTabViewPhysics extends PageScrollPhysics {
  const _MobileArtistTabViewPhysics({super.parent});

  @override
  _MobileArtistTabViewPhysics applyTo(ScrollPhysics? ancestor) {
    return _MobileArtistTabViewPhysics(parent: buildParent(ancestor));
  }

  @override
  double get minFlingDistance => 3.0;

  @override
  double get minFlingVelocity => 40.0;

  @override
  double? get dragStartDistanceMotionThreshold => 0.6;
}

class _MobileArtistTabIndicator extends Decoration {
  final Color color;
  final double width;
  final double height;
  final double radius;

  const _MobileArtistTabIndicator({
    required this.color,
    required this.width,
    required this.height,
    required this.radius,
  });

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) {
    return _MobileArtistTabIndicatorPainter(this, onChanged);
  }
}

class _MobileArtistTabIndicatorPainter extends BoxPainter {
  final _MobileArtistTabIndicator decoration;

  _MobileArtistTabIndicatorPainter(this.decoration, super.onChanged);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;

    final rect = offset & size;
    final indicatorRect = Rect.fromLTWH(
      rect.center.dx - decoration.width / 2,
      rect.bottom - decoration.height,
      decoration.width,
      decoration.height,
    );

    final paint = Paint()
      ..color = decoration.color
      ..isAntiAlias = true;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        indicatorRect,
        Radius.circular(decoration.radius),
      ),
      paint,
    );
  }
}

class _MobileArtistDetailTab extends StatelessWidget {
  final ArtistInfoData artistInfo;
  final double bottomPadding;

  const _MobileArtistDetailTab({
    required this.artistInfo,
    required this.bottomPadding,
  });

  @override
  Widget build(BuildContext context) {
    final horizontal = 14.w;
    final avatarSize = 124.w;
    final desc = artistInfo.briefDesc.trim().isEmpty
        ? '暂无简介'
        : artistInfo.briefDesc.trim();
    final hint = Theme.of(context).hintColor;
    final cardColor = hint.withValues(alpha: 0.10);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(horizontal, 2.w, horizontal, bottomPadding),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: double.infinity,
            margin: EdgeInsets.only(top: avatarSize * 0.65),
            padding: EdgeInsets.fromLTRB(14.w, avatarSize * 0.42, 14.w, 14.w),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16.w),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  artistInfo.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 22.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 12.w),
                Row(
                  children: [
                    Expanded(
                      child: _MobileArtistMetricBox(
                        label: '专辑',
                        value: '${artistInfo.albumSize}',
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: _MobileArtistMetricBox(
                        label: '单曲',
                        value: '${artistInfo.musicSize}',
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14.w),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    desc,
                    style: TextStyle(fontSize: 13.sp, height: 1.5, color: hint),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: ClipOval(
                child: CachedImage(
                  imageUrl: artistInfo.picUrl,
                  width: avatarSize,
                  height: avatarSize,
                  fit: BoxFit.cover,
                  pWidth: 320,
                  pHeight: 320,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileArtistMetricBox extends StatelessWidget {
  final String label;
  final String value;

  const _MobileArtistMetricBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 10.w),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(10.w),
      ),
      child: Center(
        child: Text(
          '$value $label',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _MobileArtistSongTab extends ConsumerWidget {
  final List<_MobileArtistSongRow> rows;
  final List<MediaItem> queueSnapshot;
  final String artistName;
  final double horizontal;

  const _MobileArtistSongTab({
    required this.rows,
    required this.queueSnapshot,
    required this.artistName,
    required this.horizontal,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeMediaId = ref.watch(
      mediaItemProvider.select((s) => s.value?.id),
    );

    if (rows.isEmpty) {
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(horizontal, 8.w, horizontal, 12.w),
        child: Text(
          '暂无热门歌曲',
          style: TextStyle(fontSize: 12.sp, color: Theme.of(context).hintColor),
        ),
      );
    }

    return CustomScrollView(
      cacheExtent: MobileArtistPage._songRowExtent.w * 8,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(horizontal, 2.w, horizontal, 10.w),
          sliver: SliverFixedExtentList(
            itemExtent: MobileArtistPage._songRowExtent.w,
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final row = rows[index];
                return _MobileArtistSongItem(
                  index: row.index + 1,
                  mediaItem: row.media,
                  isGrey: row.isGrey,
                  isActive: row.media.id == activeMediaId,
                  onTap: row.isGrey
                      ? null
                      : () => SnowfluffMusicHandler().updateQueue(
                          queueSnapshot,
                          index: row.index,
                          queueName: '$artistName 热门歌曲',
                        ),
                );
              },
              childCount: rows.length,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileArtistSongRow {
  final int index;
  final MediaItem media;
  final bool isGrey;

  const _MobileArtistSongRow({
    required this.index,
    required this.media,
    required this.isGrey,
  });
}

class _MobileArtistSongItem extends StatelessWidget {
  final int index;
  final MediaItem mediaItem;
  final VoidCallback? onTap;
  final bool isGrey;
  final bool isActive;

  const _MobileArtistSongItem({
    required this.index,
    required this.mediaItem,
    this.onTap,
    this.isGrey = false,
    this.isActive = false,
  });

  Color _resolveActiveColor(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Color.alphaBlend(
      theme.colorScheme.primary.withValues(alpha: isDark ? 0.28 : 0.14),
      theme.colorScheme.surface,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabledColor = theme.disabledColor;
    final subColor = theme.hintColor;
    final radius = BorderRadius.circular(10.w);
    final effectiveActive = isActive && !isGrey;
    final artist = (mediaItem.artist ?? '').trim();

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
          onTap: isGrey ? null : onTap,
          borderRadius: radius,
          child: Row(
            children: [
              SizedBox(
                width: 28.w,
                child: Text(
                  index.toString(),
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
                      mediaItem.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: isGrey ? disabledColor : null,
                      ),
                    ),
                    SizedBox(height: 1.w),
                    Text(
                      artist.isEmpty ? '未知歌手' : artist,
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
                _formatMobileDuration(mediaItem.duration ?? Duration.zero),
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

class _MobileArtistAlbumTab extends StatelessWidget {
  final List<ArtistAlbumCardData> albums;
  final double horizontal;

  const _MobileArtistAlbumTab({required this.albums, required this.horizontal});

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(horizontal, 8.w, horizontal, 12.w),
        child: Text(
          '暂无专辑',
          style: TextStyle(fontSize: 12.sp, color: Theme.of(context).hintColor),
        ),
      );
    }

    return CustomScrollView(
      cacheExtent: MobileArtistPage._albumRowExtent.w * 8,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(horizontal, 2.w, horizontal, 12.w),
          sliver: SliverFixedExtentList(
            itemExtent: MobileArtistPage._albumRowExtent.w,
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final album = albums[index];
                return _MobileArtistAlbumRow(
                  album: album,
                  onTap: () => context.push(AppRouter.album, extra: album.id),
                );
              },
              childCount: albums.length,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileArtistAlbumRow extends StatelessWidget {
  final ArtistAlbumCardData album;
  final VoidCallback onTap;

  const _MobileArtistAlbumRow({required this.album, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final title = album.name.isEmpty ? '未知专辑' : album.name;
    final hint = Theme.of(context).hintColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12.w),
        onTap: onTap,
        child: Ink(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.w),
          child: Row(
            children: [
              ClipOval(
                child: CachedImage(
                  imageUrl: album.picUrl,
                  width: 48.w,
                  height: 48.w,
                  fit: BoxFit.cover,
                  pWidth: 160,
                  pHeight: 160,
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2.w),
                    Text(
                      _formatPublishDateCn(album.publishTime),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.sp, color: hint),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatMobileDuration(Duration duration) {
  final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return '$mm:$ss';
}

// 平板分支
class TabletArtistPage extends ConsumerStatefulWidget {
  final ArtistInfoData artistInfo;
  final List<MediaItem> topMedias;
  final List<ArtistAlbumCardData> albumCards;
  const TabletArtistPage({
    super.key,
    required this.artistInfo,
    required this.topMedias,
    required this.albumCards,
  });
  @override
  ConsumerState<TabletArtistPage> createState() => _TabletArtistPageState();
}

class _TabletArtistPageState extends ConsumerState<TabletArtistPage> {
  // 数据快照化
  late List<MediaItem> _queueSnapshot;
  late List<_SongRowData> _songRows;
  // 专辑懒加载逻辑
  static const int _albumBatchSize = 15;
  int _visibleAlbumCount = 0;
  late ScrollController _scrollController;
  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _recomputeData(force: true);
  }
  void _recomputeData({required bool force}) {
    if (!force) return;
    _queueSnapshot = List<MediaItem>.unmodifiable(widget.topMedias);
    // 预计算歌曲行数据，避免在Builder里写逻辑
    _songRows = List.generate(_queueSnapshot.take(12).length, (i) {
      final m = _queueSnapshot[i];
      return _SongRowData(index: i, media: m, isGrey: m.extras?['isGrey'] == true);
    });
    _visibleAlbumCount = widget.albumCards.length < _albumBatchSize
        ? widget.albumCards.length
        : _albumBatchSize;
  }
  void _onScroll() {
    if (_visibleAlbumCount < widget.albumCards.length &&
        _scrollController.position.extentAfter < 600) {
      setState(() {
        _visibleAlbumCount = (_visibleAlbumCount + _albumBatchSize)
            .clamp(0, widget.albumCards.length);
      });
    }
  }
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    // 布局尺寸预计算
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = 60.w;
    final usableWidth = viewportWidth - horizontalPadding * 2;
    final coverSide = usableWidth * 3 / 11;
    return CustomScrollView(
      controller: _scrollController,
      cacheExtent: 800, // 适度预取
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: 16.w)),
        // 艺人头部
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          sliver: SliverToBoxAdapter(
            child: _TabletArtistHeader(
              info: widget.artistInfo,
              coverSide: coverSide,
              onPlay: _songRows.isEmpty ? null : () => _play(0),
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 18.w)),
        // 热门歌曲部分(Grid优化)
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          sliver: const SliverToBoxAdapter(child: _SectionTitle('热门歌曲')),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 10.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          sliver: _TabletSongGrid(
            rows: _songRows,
            queueSnapshot: _queueSnapshot,
            artistName: widget.artistInfo.name,
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 18.w)),
        // 专辑部分
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          sliver: const SliverToBoxAdapter(child: _SectionTitle('专辑')),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 10.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          sliver: _TabletAlbumGrid(
            albums: widget.albumCards.take(_visibleAlbumCount).toList(),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 16.w)),
      ],
    );
  }
  void _play(int index) {
    SnowfluffMusicHandler().updateQueue(
      _queueSnapshot,
      index: index,
      queueName: '${widget.artistInfo.name} 热门歌曲',
    );
  }
}

class _SongRowData {
  final int index;
  final MediaItem media;
  final bool isGrey;
  const _SongRowData({required this.index, required this.media, required this.isGrey});
}

class _TabletArtistHeader extends StatelessWidget {
  final ArtistInfoData info;
  final double coverSide;
  final VoidCallback? onPlay;
  const _TabletArtistHeader({required this.info, required this.coverSide, this.onPlay});
  @override
  Widget build(BuildContext context) {
    final pSize = coverSide.toInt() * 2;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CachedImage(
          imageUrl: info.picUrl,
          width: coverSide,
          height: coverSide,
          borderRadius: 16.w,
          pHeight: pSize,
          pWidth: pSize,
        ),
        SizedBox(width: 40.w),
        Expanded(
          child: SizedBox(
            height: coverSide,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(info.name, style: TextStyle(fontSize: 30.sp, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8.w),
                    Text('艺人 · ${info.musicSize}首歌 · ${info.albumSize}张专辑',
                        style: TextStyle(fontSize: 14.sp, color: Theme.of(context).hintColor)),
                    SizedBox(height: 8.w),
                  ],
                ),
                Flexible(
                  child: Text(
                    info.briefDesc.isEmpty ? '暂无简介' : info.briefDesc,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.sp, height: 1.5, color: Theme.of(context).hintColor),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('播放热门歌曲'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.w),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TabletSongGrid extends ConsumerWidget {
  final List<_SongRowData> rows;
  final List<MediaItem> queueSnapshot;
  final String artistName;
  const _TabletSongGrid({required this.rows, required this.queueSnapshot, required this.artistName});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(mediaItemProvider.select((s) => s.value?.id));
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, // 平板通常3列比较舒适
        mainAxisExtent: 64.w,
        crossAxisSpacing: 12.w,
        mainAxisSpacing: 8.w,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
        final row = rows[index];
        return _TopSongGridItem(
          media: row.media,
          isActive: row.media.id == activeId,
            onTap: row.isGrey ? null : () => SnowfluffMusicHandler().updateQueue(
                  queueSnapshot,
                  index: row.index,
                  queueName: '$artistName 热门歌曲',
                ),
        );
        },
        childCount: rows.length,
      ),
    );
  }
}

class _TabletAlbumGrid extends StatelessWidget {
  final List<ArtistAlbumCardData> albums;
  const _TabletAlbumGrid({required this.albums});
  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4, // 平板4列
        crossAxisSpacing: 20.w,
        mainAxisSpacing: 20.w,
        childAspectRatio: 0.78, // 略微调整比例以适应标题
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => _AlbumGridCard(
          album: albums[index],
          onTap: () => context.push(AppRouter.album, extra: albums[index].id),
        ),
        childCount: albums.length,
      ),
    );
  }
}
