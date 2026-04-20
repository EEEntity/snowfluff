// 个人音乐库页面

import 'package:snowfluff/common/music_handler.dart';
import 'package:snowfluff/pages/library/provider.dart';
import 'package:snowfluff/pages/playlist/provider.dart';
import 'package:snowfluff/router/app_router.dart';
import 'package:snowfluff/utils/device_config.dart';
import 'package:snowfluff/widgets/cached_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:audio_service/audio_service.dart';

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userDataAsync = ref.watch(userDataProvider);
    final playlistsAsync = ref.watch(libraryPlaylistDataProvider);
    if (userDataAsync.isLoading || playlistsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (userDataAsync.hasError || playlistsAsync.hasError) {
      return const Center(child: Text('Oops, something unexpected happened'));
    }
    final userData = userDataAsync.requireValue;
    final playlists = playlistsAsync.requireValue;
    return switch (DeviceConfig.layoutMode) {
      LayoutMode.desktop => _DesktopLibrary(
        userData: userData,
        playlistsData: playlists,
      ),
      LayoutMode.tablet => _TabletLibrary(
        userData: userData,
        playlistsData: playlists,
      ),
      _ => _MobileLibrary(userData: userData, playlistsData: playlists),
    };
  }
}

class _DesktopLibrary extends ConsumerWidget {
  final UserData userData;
  final List<LibraryPlaylistData> playlistsData;
  static const double _rowExtent = 68.0;
  const _DesktopLibrary({required this.userData, required this.playlistsData});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final normalPlaylists = playlistsData.length > 1
        ? playlistsData.sublist(1)
        : const <LibraryPlaylistData>[];
    final likedPlaylist = playlistsData.isNotEmpty ? playlistsData.first : null;
    final likedPreviewAsync = likedPlaylist == null
        ? const AsyncValue<List<MediaItem>>.data(<MediaItem>[])
        : ref.watch(likedPlaylistPreviewProvider(likedPlaylist.id));
    final likedDetailAsync = likedPlaylist == null
        ? const AsyncValue<PlaylistData?>.data(null)
        : ref
              .watch(playlistDetailProvider(likedPlaylist.id))
              .whenData((d) => d);
    final pageHorizontal = 28.w;
    return CustomScrollView(
      cacheExtent: _rowExtent * 8,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            pageHorizontal,
            12.w,
            pageHorizontal,
            12.w,
          ),
          sliver: SliverToBoxAdapter(child: _TopHeader(userData: userData)),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pageHorizontal, 0, pageHorizontal, 20.w),
          sliver: SliverToBoxAdapter(
            child: _PreviewSection(
              likedPlaylist: likedPlaylist,
              likedDetailAsync: likedDetailAsync,
              fallbackPreviewSongs:
                  likedPreviewAsync.value ?? const <MediaItem>[],
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              const crossAxisCount = 5;
              final crossSpacing = 18.w;
              final mainSpacing = 16.w;

              final tileWidth =
                  (constraints.crossAxisExtent -
                      (crossAxisCount - 1) * crossSpacing) /
                  crossAxisCount;

              // 卡片总高 = 正方形封面 + 标题 + 副标题 + 间距
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
                    final playlist = normalPlaylists[index];
                    return _PlaylistGridCard(
                      playlist: playlist,
                      onTap: () =>
                          context.push(AppRouter.playlist, extra: playlist.id),
                    );
                  },
                  childCount: normalPlaylists.length,
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

class _TopHeader extends StatelessWidget {
  final UserData userData;

  const _TopHeader({required this.userData});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CachedImage(
          imageUrl: userData.avatarUrl,
          width: 52.w,
          height: 52.w,
          borderRadius: 26.w,
          pWidth: 256,
          pHeight: 256,
        ),
        SizedBox(width: 14.w),
        Expanded(
          child: Text(
            '${userData.nickname}的音乐库',
            style: TextStyle(fontSize: 30.sp, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _PreviewSection extends StatelessWidget {
  final LibraryPlaylistData? likedPlaylist;
  final AsyncValue<PlaylistData?> likedDetailAsync;
  final List<MediaItem> fallbackPreviewSongs;

  const _PreviewSection({
    required this.likedPlaylist,
    required this.likedDetailAsync,
    required this.fallbackPreviewSongs,
  });

  @override
  Widget build(BuildContext context) {
    final likedId = likedPlaylist?.id;
    final likedTitle = likedPlaylist?.name ?? '我喜欢的音乐';
    final likedCount = likedPlaylist?.trackCount ?? 0;

    final List<MediaItem> detailSongs =
        likedDetailAsync.value?.medias ?? const <MediaItem>[];
    final bool samePreview = _sameLeadingSongIds(
      detailSongs,
      fallbackPreviewSongs,
      count: 12,
    );
    final List<MediaItem> allSongs = detailSongs.isNotEmpty
      ? detailSongs
      : fallbackPreviewSongs;
    final List<MediaItem> previewSource = (detailSongs.isNotEmpty && !samePreview)
      ? detailSongs
      : fallbackPreviewSongs;
    final List<MediaItem> previewSongs = previewSource
      .take(12)
      .toList(growable: false);

    const leftFlex = 4;
    const rightFlex = 9; // 3+3+3
    const crossAxisCount = 3;
    const rows = 4;

    final columnGap = 12.w;
    final crossSpacing = 8.w;
    final mainSpacing = 8.w;
    const itemAspect = 3.6;

    return LayoutBuilder(
      builder: (context, constraints) {
        final rightWidth =
            (constraints.maxWidth - columnGap) *
            rightFlex /
            (leftFlex + rightFlex);
        final itemWidth =
            (rightWidth - (crossAxisCount - 1) * crossSpacing) / crossAxisCount;
        final itemHeight = itemWidth / itemAspect;
        final sectionHeight = rows * itemHeight + (rows - 1) * mainSpacing;

        return SizedBox(
          height: sectionHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: leftFlex,
                child: _LikedPlaylistCard(
                  title: '我喜欢的音乐',
                  countText: '$likedCount首歌',
                  onTap: likedId == null
                      ? null
                      : () => context.push(AppRouter.playlist, extra: likedId),
                ),
              ),
              SizedBox(width: columnGap),
              Expanded(
                flex: rightFlex,
                child: GridView.builder(
                  primary: false,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 12,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: mainSpacing,
                    crossAxisSpacing: crossSpacing,
                    childAspectRatio: itemAspect,
                  ),
                  itemBuilder: (context, index) {
                    final media = index < previewSongs.length
                        ? previewSongs[index]
                        : null;
                    return _LikedSongItem(
                      media: media,
                      onTap: (media == null || likedId == null)
                          ? null
                          : () => SnowfluffMusicHandler().updateQueue(
                              allSongs,
                              index: index,
                              queueName: likedTitle,
                            ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LikedPlaylistCard extends StatelessWidget {
  final String title;
  final String countText;
  final VoidCallback? onTap;

  const _LikedPlaylistCard({
    required this.title,
    required this.countText,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12.w),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12.w),
          ),
          child: Padding(
            padding: EdgeInsets.all(14.w),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w700,
                      color: primary,
                    ),
                  ),
                  SizedBox(height: 4.w),
                  Text(
                    countText,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: primary.withValues(alpha: 0.70),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LikedSongItem extends StatefulWidget {
  final MediaItem? media;
  final VoidCallback? onTap;

  const _LikedSongItem({required this.media, this.onTap});

  @override
  State<_LikedSongItem> createState() => _LikedSongItemState();
}

class _LikedSongItemState extends State<_LikedSongItem> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    if (media == null) {
      return const SizedBox.shrink();
    }

    final bool isGrey = media.extras?['isGrey'] == true;
    final bool enabled = !isGrey;
    final hint = Theme.of(context).hintColor;
    final disabled = Theme.of(context).disabledColor;

    Widget cover = SizedBox(
      width: 42.w,
      height: 42.w,
      child: CachedImage(
        imageUrl: media.artUri?.toString() ?? '',
        borderRadius: 7.w,
        pWidth: 224,
        pHeight: 224,
      ),
    );

    if (isGrey) {
      cover = Opacity(
        opacity: 0.65,
        child: ColorFiltered(
          colorFilter: const ColorFilter.mode(
            Colors.grey,
            BlendMode.saturation,
          ),
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
              color: (hovered && enabled)
                  ? hint.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10.w),
            ),
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.w),
            child: Row(
              children: [
                cover,
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

class _PlaylistGridCard extends StatefulWidget {
  final LibraryPlaylistData playlist;
  final VoidCallback onTap;
  const _PlaylistGridCard({required this.playlist, required this.onTap});
  @override
  State<_PlaylistGridCard> createState() => _PlaylistGridCardState();
}

class _PlaylistGridCardState extends State<_PlaylistGridCard> {
  bool titleHovered = false;

  @override
  Widget build(BuildContext context) {
    final hintColor = Theme.of(context).hintColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 封面：悬停显示可点击光标，点击跳转
        Expanded(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10.w),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: CachedImage(
                    imageUrl: widget.playlist.coverUrl,
                    fit: BoxFit.cover,
                    pWidth: 256,
                    pHeight: 256,
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: 4.w),

        // 标题：悬停时下划线 + 点击指针状态
        MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => titleHovered = true),
          onExit: (_) => setState(() => titleHovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Text(
              widget.playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                decoration: titleHovered
                    ? TextDecoration.underline
                    : TextDecoration.none,
                decorationColor: Theme.of(context).textTheme.bodyMedium?.color,
                decorationThickness: 1.2,
              ),
            ),
          ),
        ),
        SizedBox(height: 2.w),

        // 歌曲数量
        Text(
          '${widget.playlist.trackCount} songs',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10.sp,
            color: hintColor,
            fontWeight: FontWeight.w400,
          ),
        ),
        SizedBox(height: 4.w),
      ],
    );
  }
}

class _TabletLibrary extends ConsumerStatefulWidget {
  final UserData userData;
  final List<LibraryPlaylistData> playlistsData;
  const _TabletLibrary({required this.userData, required this.playlistsData});
  @override
  ConsumerState<_TabletLibrary> createState() => _TabletLibraryState();
}

class _TabletLibraryState extends ConsumerState<_TabletLibrary> {
  static const double _rowExtent = 68.0;
  // 页面生命周期内不可变快照，减少build时重复sublist/对象分配
  late List<LibraryPlaylistData> _normalPlaylistsSnapshot;
  late List<_TabletPlaylistCardData> _gridRows;
  @override
  void initState() {
    super.initState();
    _recomputeSnapshots(force: true);
  }

  @override
  void didUpdateWidget(covariant _TabletLibrary oldWidget) {
    super.didUpdateWidget(oldWidget);
    _recomputeSnapshots(
      // 数据源实例变化时重算，平时滚动不重算
      force: !identical(oldWidget.playlistsData, widget.playlistsData),
    );
  }

  void _recomputeSnapshots({required bool force}) {
    if (!force) return;
    _normalPlaylistsSnapshot = widget.playlistsData.length > 1
        ? List<LibraryPlaylistData>.unmodifiable(
            widget.playlistsData.sublist(1),
          )
        : const <LibraryPlaylistData>[];
    _gridRows = List<_TabletPlaylistCardData>.unmodifiable(
      List<_TabletPlaylistCardData>.generate(_normalPlaylistsSnapshot.length, (
        i,
      ) {
        final p = _normalPlaylistsSnapshot[i];
        return _TabletPlaylistCardData(
          id: p.id,
          name: p.name,
          coverUrl: p.coverUrl,
          trackCount: p.trackCount,
        );
      }, growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final likedPlaylist = widget.playlistsData.isNotEmpty
        ? widget.playlistsData.first
        : null;
    final likedPreviewAsync = likedPlaylist == null
        ? const AsyncValue<List<MediaItem>>.data(<MediaItem>[])
        : ref.watch(likedPlaylistPreviewProvider(likedPlaylist.id));
    final likedDetailAsync = likedPlaylist == null
        ? const AsyncValue<PlaylistData?>.data(null)
        : ref
              .watch(playlistDetailProvider(likedPlaylist.id))
              .whenData((d) => d);
    final likedId = likedPlaylist?.id;
    final likedTitle = likedPlaylist?.name ?? '我喜欢的音乐';
    final likedCount = likedPlaylist?.trackCount ?? 0;
    final List<MediaItem> detailSongs =
        likedDetailAsync.value?.medias ?? const <MediaItem>[];
    final List<MediaItem> fallbackSongs =
        likedPreviewAsync.value ?? const <MediaItem>[];
    final bool samePreview = _sameLeadingSongIds(
      detailSongs,
      fallbackSongs,
      count: 12,
    );
    final List<MediaItem> allSongs = detailSongs.isNotEmpty
        ? detailSongs
        : fallbackSongs;
    final List<MediaItem> previewSource = (detailSongs.isNotEmpty && !samePreview)
        ? detailSongs
        : fallbackSongs;
    final previewSongs = List<MediaItem>.unmodifiable(
      previewSource.length > 12 ? previewSource.sublist(0, 12) : previewSource,
    );
    // 平板尺寸一次性计算，避免在滚动中频繁触发LayoutBuilder开销
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final pageHorizontal = 60.w;
    final usableWidth = (viewportWidth - pageHorizontal * 2).clamp(
      0.0,
      double.infinity,
    );
    final gridCrossAxisCount = 4;
    final gridCrossSpacing = 20.w;
    final gridMainSpacing = 14.w;
    final gridTileWidth =
        ((usableWidth - (gridCrossAxisCount - 1) * gridCrossSpacing) /
                gridCrossAxisCount)
            .clamp(0.0, double.infinity);
    final gridTileHeight = gridTileWidth + 4.w + 18.w + 2.w + 16.w + 4.w;
    // 预览区参数(左：喜欢卡片；右：12首歌曲)
    const leftFlex = 4;
    const rightFlex = 9;
    const previewCrossAxisCount = 3;
    const previewRows = 4;
    const previewAspect = 3.6;

    final previewColumnGap = 10.w;
    final previewCrossSpacing = 8.w;
    final previewMainSpacing = 8.w;

    final rightWidth =
        ((usableWidth - previewColumnGap) * rightFlex / (leftFlex + rightFlex))
            .clamp(0.0, double.infinity);
    final previewItemWidth =
        ((rightWidth - (previewCrossAxisCount - 1) * previewCrossSpacing) /
                previewCrossAxisCount)
            .clamp(0.0, double.infinity);
    final previewItemHeight = (previewItemWidth / previewAspect).clamp(
      0.0,
      double.infinity,
    );
    final previewSectionHeight =
        previewRows * previewItemHeight +
        (previewRows - 1) * previewMainSpacing;

    return CustomScrollView(
      // 平板端适当预取，减少滚动过程抖动
      cacheExtent: _rowExtent * 10,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            pageHorizontal,
            10.w,
            pageHorizontal,
            10.w,
          ),
          sliver: SliverToBoxAdapter(
            child: _TopHeader(userData: widget.userData),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pageHorizontal, 0, pageHorizontal, 30.w),
          sliver: SliverToBoxAdapter(
            child: _TabletPreviewSection(
              sectionHeight: previewSectionHeight,
              columnGap: previewColumnGap,
              crossAxisCount: previewCrossAxisCount,
              crossSpacing: previewCrossSpacing,
              mainSpacing: previewMainSpacing,
              itemAspect: previewAspect,
              likedId: likedId,
              likedCount: likedCount,
              likedTitle: likedTitle,
              allSongs: allSongs,
              previewSongs: previewSongs,
            ),
          ),
        ),
        if (_gridRows.isEmpty)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
            sliver: SliverToBoxAdapter(
              child: Text(
                '暂无歌单数据',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: gridCrossAxisCount,
                crossAxisSpacing: gridCrossSpacing,
                mainAxisSpacing: gridMainSpacing,
                mainAxisExtent: gridTileHeight,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final row = _gridRows[index];
                  return _TabletPlaylistGridCard(
                    row: row,
                    coverSide: gridTileWidth,
                    onCoverTap: () =>
                        context.push(AppRouter.playlist, extra: row.id),
                  );
                },
                childCount: _gridRows.length,
                addRepaintBoundaries: true,
                addAutomaticKeepAlives: false,
              ),
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: 20.w)),
      ],
    );
  }
}

class _TabletPlaylistCardData {
  final int id;
  final String name;
  final String coverUrl;
  final int trackCount;

  const _TabletPlaylistCardData({
    required this.id,
    required this.name,
    required this.coverUrl,
    required this.trackCount,
  });
}

class _TabletPreviewSection extends StatelessWidget {
  final double sectionHeight;
  final double columnGap;
  final int crossAxisCount;
  final double crossSpacing;
  final double mainSpacing;
  final double itemAspect;

  final int? likedId;
  final int likedCount;
  final String likedTitle;
  final List<MediaItem> allSongs;
  final List<MediaItem> previewSongs;

  const _TabletPreviewSection({
    required this.sectionHeight,
    required this.columnGap,
    required this.crossAxisCount,
    required this.crossSpacing,
    required this.mainSpacing,
    required this.itemAspect,
    required this.likedId,
    required this.likedCount,
    required this.likedTitle,
    required this.allSongs,
    required this.previewSongs,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: sectionHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 4,
            child: _LikedPlaylistCard(
              title: '我喜欢的音乐',
              countText: '$likedCount首歌',
              onTap: likedId == null
                  ? null
                  : () => context.push(AppRouter.playlist, extra: likedId),
            ),
          ),
          SizedBox(width: columnGap),
          Expanded(
            flex: 9,
            child: GridView.builder(
              primary: false,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 12,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: mainSpacing,
                crossAxisSpacing: crossSpacing,
                childAspectRatio: itemAspect,
              ),
              itemBuilder: (context, index) {
                final media = index < previewSongs.length
                    ? previewSongs[index]
                    : null;
                return _TabletLikedSongItem(
                  media: media,
                  onTap: (media == null || likedId == null)
                      ? null
                      : () => SnowfluffMusicHandler().updateQueue(
                          allSongs,
                          index: index,
                          queueName: likedTitle,
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TabletLikedSongItem extends StatelessWidget {
  final MediaItem? media;
  final VoidCallback? onTap;

  const _TabletLikedSongItem({required this.media, this.onTap});

  @override
  Widget build(BuildContext context) {
    final m = media;
    if (m == null) return const SizedBox.shrink();

    final isGrey = m.extras?['isGrey'] == true;
    final enabled = !isGrey;
    final hint = Theme.of(context).hintColor;
    final disabled = Theme.of(context).disabledColor;

    Widget cover = SizedBox(
      width: 42.w,
      height: 42.w,
      child: CachedImage(
        imageUrl: m.artUri?.toString() ?? '',
        borderRadius: 7.w,
        pWidth: 224,
        pHeight: 224,
      ),
    );

    if (isGrey) {
      cover = Opacity(
        opacity: 0.65,
        child: ColorFiltered(
          colorFilter: const ColorFilter.mode(
            Colors.grey,
            BlendMode.saturation,
          ),
          child: cover,
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10.w),
        onTap: enabled ? onTap : null,
        child: Ink(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.w),
          child: Row(
            children: [
              cover,
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: isGrey ? disabled : null,
                      ),
                    ),
                    SizedBox(height: 2.w),
                    Text(
                      m.artist ?? '',
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
    );
  }
}

class _TabletPlaylistGridCard extends StatelessWidget {
  final _TabletPlaylistCardData row;
  final double coverSide;
  final VoidCallback onCoverTap;
  const _TabletPlaylistGridCard({
    required this.row,
    required this.coverSide,
    required this.onCoverTap,
  });
  @override
  Widget build(BuildContext context) {
    final hintColor = Theme.of(context).hintColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onCoverTap,
          child: SizedBox(
            width: coverSide,
            height: coverSide,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10.w),
              child: CachedImage(
                imageUrl: row.coverUrl,
                fit: BoxFit.cover,
                pHeight: 512,
                pWidth: 512,
              ),
            ),
          ),
        ),
        SizedBox(height: 4.w),
        Text(
          row.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 2.w),
        Text(
          '${row.trackCount} songs',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10.sp,
            color: hintColor,
            fontWeight: FontWeight.w400,
          ),
        ),
        SizedBox(height: 4.w),
      ],
    );
  }
}

class _MobileLibrary extends StatefulWidget {
  final UserData userData;
  final List<LibraryPlaylistData> playlistsData;

  const _MobileLibrary({required this.userData, required this.playlistsData});

  @override
  State<_MobileLibrary> createState() => _MobileLibraryState();
}

class _MobileLibraryState extends State<_MobileLibrary> {
  static const double _itemExtent = 72.0;

  LibraryPlaylistData? _likedPlaylist;
  late List<LibraryPlaylistData> _otherPlaylists;

  @override
  void initState() {
    super.initState();
    _recomputeSnapshots(force: true);
  }

  @override
  void didUpdateWidget(covariant _MobileLibrary oldWidget) {
    super.didUpdateWidget(oldWidget);
    _recomputeSnapshots(
      force: !identical(oldWidget.playlistsData, widget.playlistsData),
    );
  }

  void _recomputeSnapshots({required bool force}) {
    if (!force) return;
    _likedPlaylist = widget.playlistsData.isNotEmpty
        ? widget.playlistsData.first
        : null;
    _otherPlaylists = widget.playlistsData.length > 1
        ? List<LibraryPlaylistData>.unmodifiable(
            widget.playlistsData.sublist(1),
          )
        : const <LibraryPlaylistData>[];
  }

  @override
  Widget build(BuildContext context) {
    final pageHorizontal = 14.w;
    final pageTitle = '${widget.userData.nickname}的音乐库';
    return CustomScrollView(
      // 手机上控制预取范围，兼顾滚动流畅与内存占用
      cacheExtent: _itemExtent * 12,
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: 6.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: SliverToBoxAdapter(
            child: Text(
              pageTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 16.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: const SliverToBoxAdapter(
            child: _MobileSectionHeader(title: '喜欢的音乐'),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 6.w)),
        if (_likedPlaylist == null)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
            sliver: SliverToBoxAdapter(
              child: Text(
                '暂无歌单数据',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
            sliver: SliverFixedExtentList(
              itemExtent: _itemExtent,
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final playlist = _likedPlaylist!;
                  return _MobileMeidaItem(
                    playlist: playlist,
                    onTap: () =>
                        context.push(AppRouter.playlist, extra: playlist.id),
                  );
                },
                childCount: 1,
                addRepaintBoundaries: true,
                addAutomaticKeepAlives: false,
              ),
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: 14.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: const SliverToBoxAdapter(
            child: _MobileSectionHeader(title: '我的歌单'),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 6.w)),
        if (_otherPlaylists.isEmpty)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
            sliver: SliverToBoxAdapter(
              child: Text(
                '暂无更多歌单',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
            sliver: SliverFixedExtentList(
              itemExtent: _itemExtent,
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final playlist = _otherPlaylists[index];
                  return _MobileMeidaItem(
                    playlist: playlist,
                    onTap: () =>
                        context.push(AppRouter.playlist, extra: playlist.id),
                  );
                },
                childCount: _otherPlaylists.length,
                addRepaintBoundaries: true,
                addAutomaticKeepAlives: false,
              ),
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: 20.w)),
      ],
    );
  }
}

class _MobileSectionHeader extends StatelessWidget {
  final String title;

  const _MobileSectionHeader({required this.title});

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

class _MobileMeidaItem extends StatelessWidget {
  final LibraryPlaylistData playlist;
  final VoidCallback onTap;

  const _MobileMeidaItem({required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hintColor = Theme.of(context).hintColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12.w),
        onTap: onTap,
        child: Ink(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.w),
          child: Row(
            children: [
              SizedBox(width: 4.w),
              ClipOval(
                child: CachedImage(
                  imageUrl: playlist.coverUrl,
                  width: 46.w,
                  height: 46.w,
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
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2.w),
                    Text(
                      '${playlist.trackCount} Songs',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.sp, color: hintColor),
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

bool _sameLeadingSongIds(
  List<MediaItem> a,
  List<MediaItem> b, {
  required int count,
}) {
  if (a.isEmpty || b.isEmpty) return false;
  final int n = a.length < b.length ? a.length : b.length;
  final int limit = n < count ? n : count;
  if (limit <= 0) return false;
  for (int i = 0; i < limit; i++) {
    if (a[i].id != b[i].id) return false;
  }
  return true;
}
