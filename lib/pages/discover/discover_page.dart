// 发现页面

import 'package:snowfluff/common/music_handler.dart';
import 'package:snowfluff/pages/discover/provider.dart';
import 'package:snowfluff/pages/provider.dart';
import 'package:snowfluff/router/app_router.dart';
import 'package:snowfluff/utils/device_config.dart';
import 'package:snowfluff/widgets/cached_image.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

class DiscoverPage extends ConsumerWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(recommendPlaylistsProvider);
    final songsAsync = ref.watch(songsProvider);

    if (playlistsAsync.isLoading || songsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (playlistsAsync.hasError || songsAsync.hasError) {
      return const Center(child: Text('Oops, something unexpected happened'));
    }

    final playlists = playlistsAsync.requireValue;
    final songs = songsAsync.requireValue;

    return switch (DeviceConfig.layoutMode) {
      LayoutMode.desktop => _DesktopDiscover(playlists: playlists, songs: songs),
      LayoutMode.tablet => _TabletDiscover(playlists: playlists, songs: songs),
      LayoutMode.mobile => _MobileDiscover(playlists: playlists, songs: songs),
    };
  }
}

class _DesktopDiscover extends StatelessWidget {
  static const int _playlistSlotCount = 8; // 2 x 4
  static const int _songSlotCount = 30; // 6 x 5
  static const double _rowExtent = 68.0;

  final List<RecommendPlaylistCardData> playlists;
  final List<MediaItem> songs;

  const _DesktopDiscover({
    required this.playlists,
    required this.songs,
  });

  @override
  Widget build(BuildContext context) {
    final pageHorizontal = 30.w;
    final playlistHorizontal = 40.w;
    final visiblePlaylists = playlists.take(_playlistSlotCount).toList(growable: false);
    final visibleSongs = songs.take(_songSlotCount).toList(growable: false);

    return CustomScrollView(
      cacheExtent: _rowExtent * 12,
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: 18.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: const SliverToBoxAdapter(
            child: _SurfaceTitle('推荐歌单'),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 12.w)),
        if (visiblePlaylists.isEmpty)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: playlistHorizontal),
            sliver: SliverToBoxAdapter(
              child: Text(
                ' 暂无数据',
                style: TextStyle(fontSize: 12.sp, color: Theme.of(context).hintColor),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: playlistHorizontal),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                const crossAxisCount = 4;
                final crossSpacing = 22.w;
                final mainSpacing = 18.w;

                final tileWidth =
                    (constraints.crossAxisExtent - (crossAxisCount - 1) * crossSpacing) /
                        crossAxisCount;
                final tileHeight = tileWidth + 4.w + 18.w + 4.w;

                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: crossSpacing,
                    mainAxisSpacing: mainSpacing,
                    mainAxisExtent: tileHeight,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index >= visiblePlaylists.length) {
                        return const SizedBox.shrink();
                      }
                      final playlist = visiblePlaylists[index];
                      return _RecommendPlaylistCard(
                        data: playlist,
                        onTap: () => context.push(AppRouter.playlist, extra: playlist.id),
                      );
                    },
                    childCount: _playlistSlotCount,
                    addRepaintBoundaries: true,
                    addAutomaticKeepAlives: false,
                  ),
                );
              },
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: 28.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: const SliverToBoxAdapter(
            child: _SurfaceTitle('私人FM'),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 12.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: const SliverToBoxAdapter(
            child: _PersonalFMBar(),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 28.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: const SliverToBoxAdapter(
            child: _SurfaceTitle('每日推荐歌曲'),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 12.w)),
        if (visibleSongs.isEmpty)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
            sliver: SliverToBoxAdapter(
              child: Text(
                ' 暂无数据',
                style: TextStyle(fontSize: 12.sp, color: Theme.of(context).hintColor),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                const crossAxisCount = 5;
                final crossSpacing = 10.w;
                final mainSpacing = 8.w;
                const itemAspect = 3.35;

                final itemWidth =
                    (constraints.crossAxisExtent - (crossAxisCount - 1) * crossSpacing) /
                        crossAxisCount;
                final itemHeight = (itemWidth / itemAspect).clamp(58.w, 92.w).toDouble();

                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: crossSpacing,
                    mainAxisSpacing: mainSpacing,
                    mainAxisExtent: itemHeight,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final media = index < visibleSongs.length ? visibleSongs[index] : null;
                      return _DailySongGridItem(
                        media: media,
                        onTap: media == null
                            ? null
                            : () => SnowfluffMusicHandler().updateQueue(
                                  visibleSongs,
                                  index: index,
                                  queueName: '每日推荐歌曲',
                                ),
                      );
                    },
                    childCount: _songSlotCount,
                    addRepaintBoundaries: true,
                    addAutomaticKeepAlives: false,
                  ),
                );
              },
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: 20.w)),
      ],
    );
  }
}

class _SurfaceTitle extends StatelessWidget {
  final String title;

  const _SurfaceTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700),
    );
  }
}

class _PersonalFMBar extends StatefulWidget {
  const _PersonalFMBar();

  @override
  State<_PersonalFMBar> createState() => _PersonalFMBarState();
}

class _PersonalFMBarState extends State<_PersonalFMBar> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10.w),
          onTap: () {
            if (!SnowfluffMusicHandler().isFMMode) {
              SnowfluffMusicHandler().enterFMMode();
            }
          },
          child: Ink(
            decoration: BoxDecoration(
              color: _hovered ? hint.withValues(alpha: 0.18) : Colors.transparent,
              borderRadius: BorderRadius.circular(10.w),
            ),
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 12.w),
            child: Row(
              children: [
                Icon(Icons.radio, size: 20.w),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    '网易云音乐，听见好时光',
                    style: TextStyle(fontSize: 13.sp),
                  ),
                ),
                Icon(Icons.all_inclusive, size: 20.w, color: hint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecommendPlaylistCard extends StatefulWidget {
  final RecommendPlaylistCardData data;
  final VoidCallback onTap;

  const _RecommendPlaylistCard({
    required this.data,
    required this.onTap,
  });

  @override
  State<_RecommendPlaylistCard> createState() => _RecommendPlaylistCardState();
}

class _RecommendPlaylistCardState extends State<_RecommendPlaylistCard> {
  bool _titleHovered = false;

  @override
  Widget build(BuildContext context) {
    final title = widget.data.title.isEmpty ? '未知歌单' : widget.data.title;

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
                      imageUrl: widget.data.coverUrl,
                      fit: BoxFit.cover,
                      pWidth: 384,
                      pHeight: 384,
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
          onEnter: (_) => setState(() => _titleHovered = true),
          onExit: (_) => setState(() => _titleHovered = false),
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
                decoration: _titleHovered ? TextDecoration.underline : TextDecoration.none,
                decorationThickness: 1.2,
                decorationColor: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
          ),
        ),
        SizedBox(height: 4.w),
      ],
    );
  }
}

class _DailySongGridItem extends StatefulWidget {
  final MediaItem? media;
  final VoidCallback? onTap;

  const _DailySongGridItem({
    required this.media,
    this.onTap,
  });

  @override
  State<_DailySongGridItem> createState() => _DailySongGridItemState();
}

class _DailySongGridItemState extends State<_DailySongGridItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    if (media == null) {
      return const SizedBox.shrink();
    }

    final bool isGrey = media.extras?['isGrey'] == true;
    final bool enabled = !isGrey && widget.onTap != null;
    final hint = Theme.of(context).hintColor;
    final disabled = Theme.of(context).disabledColor;

    Widget cover = SizedBox(
      width: 42.w,
      height: 42.w,
      child: CachedImage(
        imageUrl: media.artUri?.toString() ?? '',
        fit: BoxFit.cover,
        borderRadius: 7.w,
        pWidth: 224,
        pHeight: 224,
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
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10.w),
          onTap: enabled ? widget.onTap : null,
          child: Ink(
            decoration: BoxDecoration(
              color: (_hovered && enabled) ? hint.withValues(alpha: 0.18) : Colors.transparent,
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
                          color: isGrey ? disabled : null,
                        ),
                      ),
                      SizedBox(height: 2.w),
                      Text(
                        media.artist ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: isGrey ? disabled : hint,
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

// 平板
class _TabletDiscover extends StatelessWidget {
  static const int _playlistSlotCount = 8; // 2 x 4
  static const int _songSlotCount = 30; // 6 x 5
  static const double _rowExtent = 68.0;
  final List<RecommendPlaylistCardData> playlists;
  final List<MediaItem> songs;
  const _TabletDiscover({
    required this.playlists,
    required this.songs,
  });

  @override
  Widget build(BuildContext context) {
    final pageHorizontal = 60.w;
    final playlistHorizontal = 80.w;
    final visiblePlaylists = playlists.take(_playlistSlotCount).toList(growable: false);
    final visibleSongs = songs.take(_songSlotCount).toList(growable: false);
    // 只依赖屏幕宽度计算一次，不在滚动期间反复走SliverLayoutBuilder
    final viewportWidth = MediaQuery.sizeOf(context).width;
    const playlistCrossAxisCount = 4;
    final playlistCrossSpacing = 16.w;
    final playlistMainSpacing = 14.w;
    final playlistGridWidth = viewportWidth - playlistHorizontal * 2;
    final playlistTileWidth =
        (playlistGridWidth - (playlistCrossAxisCount - 1) * playlistCrossSpacing) /
            playlistCrossAxisCount;
    final playlistTileHeight = playlistTileWidth + 4.w + 18.w + 4.w;
    const songCrossAxisCount = 5;
    final songCrossSpacing = 8.w;
    final songMainSpacing = 8.w;
    const songItemAspect = 3.35;
    final songGridWidth = viewportWidth - pageHorizontal * 2;
    final songItemWidth =
        (songGridWidth - (songCrossAxisCount - 1) * songCrossSpacing) / songCrossAxisCount;
    final songItemHeight = (songItemWidth / songItemAspect).clamp(56.w, 88.w).toDouble();

    return CustomScrollView(
      cacheExtent: _rowExtent * 8,
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(height: 4.w),
        ),
        SliverPadding(
          padding: EdgeInsetsGeometry.symmetric(horizontal: pageHorizontal),
          sliver: const SliverToBoxAdapter(
            child: _SurfaceTitle('推荐歌单'),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(height: 10.w),
        ),
        if (visiblePlaylists.isEmpty)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: playlistHorizontal),
            sliver: SliverToBoxAdapter(
              child: Text(
                '暂无每日歌单数据',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Theme.of(context).hintColor
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: playlistHorizontal),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: playlistCrossAxisCount,
                crossAxisSpacing: playlistCrossSpacing,
                mainAxisSpacing: playlistMainSpacing,
                mainAxisExtent: playlistTileHeight,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final playlist = visiblePlaylists[index];
                  return _TabletRecommendPlaylistCard(
                    key: ValueKey(playlist.id),
                    data: playlist,
                    onTap: () => context.push(AppRouter.playlist, extra: playlist.id),
                  );
                },
                childCount: visiblePlaylists.length,
                addRepaintBoundaries: true,
                addAutomaticKeepAlives: false,
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: SizedBox(height: 24.w),
        ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: const SliverToBoxAdapter(
            child: _SurfaceTitle('私人FM'),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 10.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: const SliverToBoxAdapter(
            child: _PersonalFMBar(),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(height: 24.w),
        ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: const SliverToBoxAdapter(child: _SurfaceTitle('每日推荐歌曲')),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 10.w)),
        if (visibleSongs.isEmpty)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
            sliver: SliverToBoxAdapter(
              child: Text(
                ' 暂无每日歌曲数据',
                style: TextStyle(fontSize: 12.sp, color: Theme.of(context).hintColor),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: songCrossAxisCount,
                crossAxisSpacing: songCrossSpacing,
                mainAxisSpacing: songMainSpacing,
                mainAxisExtent: songItemHeight,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final media = visibleSongs[index];
                  return _TabletDailySongGridItem(
                    key: ValueKey(media.id),
                    media: media,
                    onTap: media.extras?['isGrey'] == true
                        ? null
                        : () => SnowfluffMusicHandler().updateQueue(
                              visibleSongs,
                              index: index,
                              queueName: '每日推荐歌曲',
                            ),
                  );
                },
                childCount: visibleSongs.length,
                addRepaintBoundaries: true,
                addAutomaticKeepAlives: false,
              ),
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: 16.w)),
      ],
    );
  }
}

class _TabletRecommendPlaylistCard extends StatelessWidget {
  final RecommendPlaylistCardData data;
  final VoidCallback onTap;
  const _TabletRecommendPlaylistCard({
    super.key,
    required this.data,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final title = data.title.isEmpty ? '未知歌单' : data.title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10.w),
              child: RepaintBoundary(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: CachedImage(
                    imageUrl: data.coverUrl,
                    fit: BoxFit.cover,
                    pWidth: 320,
                    pHeight: 320,
                    enableFade: false,
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: 4.w),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(height: 4.w),
      ],
    );
  }
}

class _TabletDailySongGridItem extends StatelessWidget {
  final MediaItem media;
  final VoidCallback? onTap;
  const _TabletDailySongGridItem({
    super.key,
    required this.media,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final bool isGrey = media.extras?['isGrey'] == true;
    final bool enabled = !isGrey && onTap != null;
    final hint = Theme.of(context).hintColor;
    final disabled = Theme.of(context).disabledColor;
    Widget cover = SizedBox(
      width: 40.w,
      height: 40.w,
      child: CachedImage(
        imageUrl: media.artUri?.toString() ?? '',
        fit: BoxFit.cover,
        borderRadius: 7.w,
        pWidth: 96,
        pHeight: 96,
        enableFade: false,
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
    final staticContent = RepaintBoundary(
      child: Padding(
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
                      color: isGrey ? disabled : null,
                    ),
                  ),
                  SizedBox(height: 2.w),
                  Text(
                    media.artist ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: isGrey ? disabled : hint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10.w)
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            staticContent,
            Positioned.fill(
              child: InkWell(
                borderRadius: BorderRadius.circular(10.w),
                onTap: enabled ? onTap : null,
              ),
            )
          ],
        ),
      ),
    );
  }
}

// 手机端
class _MobileDiscover extends StatelessWidget {
  static const int _playlistCount = 6; // 3 × 2
  static const double _songRowExtent = 58.0;
  final List<RecommendPlaylistCardData> playlists;
  final List<MediaItem> songs;
  const _MobileDiscover({required this.playlists, required this.songs});

  @override
  Widget build(BuildContext context) {
    final pageHorizontal = 14.w;
    final viewportWidth = MediaQuery.sizeOf(context).width;

    // 歌单网格尺寸(预算，不走SliverLayoutBuilder)
    const crossAxisCount = 3;
    final crossSpacing = 10.w;
    final mainSpacing = 12.w;
    final gridWidth = viewportWidth - pageHorizontal * 2;
    final tileWidth =
        (gridWidth - (crossAxisCount - 1) * crossSpacing) / crossAxisCount;
    // 2行标题 ≈ 12sp * 1.35 * 2 + 少量余量
    final tileHeight = tileWidth + 4.w + 34.w + 4.w;

    final visiblePlaylists =
        playlists.take(_playlistCount).toList(growable: false);

    return CustomScrollView(
      cacheExtent: _songRowExtent.w * 12,
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: 6.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: SliverToBoxAdapter(
            child: Text(
              '每日发现',
              style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 16.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: const SliverToBoxAdapter(
            child: _MobileSectionDot('推荐歌单'),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 8.w)),
        if (visiblePlaylists.isEmpty)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
            sliver: SliverToBoxAdapter(
              child: Text(
                '暂无数据',
                style: TextStyle(
                    fontSize: 12.sp, color: Theme.of(context).hintColor),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: crossSpacing,
                mainAxisSpacing: mainSpacing,
                mainAxisExtent: tileHeight,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final playlist = visiblePlaylists[index];
                  return _MobilePlaylistCard(
                    key: ValueKey(playlist.id),
                    data: playlist,
                    onTap: () =>
                        context.push(AppRouter.playlist, extra: playlist.id),
                  );
                },
                childCount: visiblePlaylists.length,
                addRepaintBoundaries: true,
                addAutomaticKeepAlives: false,
              ),
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: 20.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: const SliverToBoxAdapter(
            child: _MobileSectionDot('私人FM'),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 8.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: const SliverToBoxAdapter(child: _MobileFMBar()),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 20.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: const SliverToBoxAdapter(
            child: _MobileSectionDot('每日推荐歌曲'),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 8.w)),
        if (songs.isEmpty)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
            sliver: SliverToBoxAdapter(
              child: Text(
                '暂无数据',
                style: TextStyle(
                    fontSize: 12.sp, color: Theme.of(context).hintColor),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
            sliver: _MobileDailySongSliver(songs: songs),
          ),
        SliverToBoxAdapter(child: SizedBox(height: 20.w)),
      ],
    );
  }
}

class _MobileSectionDot extends StatelessWidget {
  final String title;

  const _MobileSectionDot(this.title);

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Container(
          width: 8.w,
          height: 8.w,
          decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
        ),
        SizedBox(width: 8.w),
        Text(
          title,
          style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _MobileFMBar extends StatelessWidget {
  const _MobileFMBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12.w),
        onTap: () {
          if (!SnowfluffMusicHandler().isFMMode) {
            SnowfluffMusicHandler().enterFMMode();
          }
        },
        child: Ink(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12.w),
          ),
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.w),
          child: Row(
            children: [
              Icon(Icons.radio, size: 22.w),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(
                  '网易云音乐，听见好时光',
                  style: TextStyle(fontSize: 14.sp),
                ),
              ),
              Icon(Icons.all_inclusive,
                  size: 22.w, color: theme.hintColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobilePlaylistCard extends StatelessWidget {
  final RecommendPlaylistCardData data;
  final VoidCallback onTap;

  const _MobilePlaylistCard({
    super.key,
    required this.data,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = data.title.isEmpty ? '未知歌单' : data.title;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8.w),
              child: RepaintBoundary(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: CachedImage(
                    imageUrl: data.coverUrl,
                    fit: BoxFit.cover,
                    pWidth: 256,
                    pHeight: 256,
                    enableFade: false,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 4.w),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 4.w),
        ],
      ),
    );
  }
}

class _MobileDailySongSliver extends ConsumerWidget {
  static const double _rowExtent = 58.0;

  final List<MediaItem> songs;

  const _MobileDailySongSliver({required this.songs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeMediaId =
        ref.watch(mediaItemProvider.select((s) => s.value?.id));

    return SliverFixedExtentList(
      itemExtent: _rowExtent.w,
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final media = songs[index];
          final isGrey = media.extras?['isGrey'] == true;
          return _MobileSongRow(
            index: index + 1,
            media: media,
            isGrey: isGrey,
            isActive: media.id == activeMediaId,
            onTap: isGrey
                ? null
                : () => SnowfluffMusicHandler().updateQueue(
                      songs,
                      index: index,
                      queueName: '每日推荐歌曲',
                    ),
          );
        },
        childCount: songs.length,
        addRepaintBoundaries: true,
        addAutomaticKeepAlives: false,
      ),
    );
  }
}

class _MobileSongRow extends StatelessWidget {
  final int index;
  final MediaItem media;
  final bool isGrey;
  final bool isActive;
  final VoidCallback? onTap;

  const _MobileSongRow({
    required this.index,
    required this.media,
    required this.isGrey,
    required this.isActive,
    this.onTap,
  });

  static Color _activeColor(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Color.alphaBlend(
      theme.colorScheme.primary.withValues(alpha: isDark ? 0.28 : 0.14),
      theme.colorScheme.surface,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveActive = isActive && !isGrey;
    final disabledColor = theme.disabledColor;
    final subColor = theme.hintColor;
    final radius = BorderRadius.circular(10.w);
    final artist = (media.artist ?? '').trim();

    return Material(
      type: MaterialType.transparency,
      shape: RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          color: effectiveActive ? _activeColor(theme) : Colors.transparent,
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
                _formatSongDuration(media.duration ?? Duration.zero),
                style: TextStyle(
                  fontSize: 11.sp,
                  color: isGrey ? disabledColor : null,
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

String _formatSongDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
