// 歌单详情页面

import 'package:snowfluff/common/music_handler.dart';
import 'package:snowfluff/pages/playlist/provider.dart';
import 'package:snowfluff/pages/provider.dart';
import 'package:snowfluff/utils/device_config.dart';
import 'package:snowfluff/widgets/cached_image.dart';
import 'package:snowfluff/widgets/loading_indicator.dart';
import 'package:snowfluff/widgets/media_item_widget.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class PlaylistPage extends ConsumerWidget {
  final int id;
  const PlaylistPage(
    this.id,
    {super.key}
  );
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref.watch(playlistDetailProvider(id));
    return playlist.when(
      data: (details) => switch (DeviceConfig.layoutMode) {
        LayoutMode.desktop => DesktopPlayList(playlistData: details),
        LayoutMode.tablet => TabletPlaylist(playlistData: details),
        LayoutMode.mobile => MobilePlaylist(playlistData: details),
      },
      loading: () => const Center(child: LoadingIndicator()),
      error: (_, _) => const Center(child: Text('Something playlist wrong...'))
    );
  }
}

class DesktopPlayList extends ConsumerWidget {
  final PlaylistData playlistData;
  static const double _rowExtent = 68.0; // 固定64行高+4底部间距
  const DesktopPlayList({
    super.key,
    required this.playlistData,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeMediaId = ref.watch(mediaItemProvider.select((s) => s.value?.id));
    return CustomScrollView(
      // 仅预构建少量屏外内容，减少内存&提高流畅度
      cacheExtent: _rowExtent * 8,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 20.w),
          sliver: SliverToBoxAdapter(
            child: _PlaylistHeader(playlistData: playlistData),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 40.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          sliver: SliverFixedExtentList(
            // itemExtent: _rowExtent,
            itemExtent: 68.w,
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final media = playlistData.medias[index];
                final isGrey = media.extras?['isGrey'] == true;
                return Padding(
                  padding: EdgeInsets.only(bottom: 4.w),
                  child: MediaItemWidget(
                    mediaItem: media,
                    isGrey: isGrey,
                    isActive: media.id == activeMediaId,
                    onTap: isGrey
                      ? null
                      : () => SnowfluffMusicHandler().updateQueue(
                        playlistData.medias,
                        index: index,
                        queueName: playlistData.title,
                      ),
                  ),
                );
              },
              childCount: playlistData.medias.length,
              addRepaintBoundaries: true,
              addAutomaticKeepAlives: false, // 或许能减小内存，但可能造成闪烁&高耗电
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(height: 20.w),
        )
      ],
    );
  }
}

class _PlaylistHeader extends StatelessWidget {
  final PlaylistData playlistData;

  const _PlaylistHeader({
    required this.playlistData,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const totalFlex = 11; // 3:8
        final coverSide = (constraints.maxWidth - 40.w) * 3 / totalFlex;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: AspectRatio(
                aspectRatio: 1,
                child: CachedImage(
                  imageUrl: playlistData.coverUrl,
                  borderRadius: 12.w,
                  pWidth: 1024,
                  pHeight: 1024,
                ),
              ),
            ),
            SizedBox(width: 40.w),
            Expanded(
              flex: 8,
              child: SizedBox(
                height: coverSide,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 10.w),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  if (playlistData.isPrivate) ...[
                                    Icon(
                                      Icons.lock,
                                      size: 28.w,
                                      color: Theme.of(context).hintColor,
                                    ),
                                    SizedBox(width: 8.w),
                                  ],
                                  Expanded(
                                    child: Text(
                                      playlistData.title,
                                      style: TextStyle(
                                        fontSize: 32.sp,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 15.w),
                        Text(
                          playlistData.description == '' ? '暂无描述' : playlistData.description,
                          style: TextStyle(
                            fontSize: 16.sp,
                            color: Theme.of(context).hintColor,
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: () {
                        SnowfluffMusicHandler().updateQueue(
                          playlistData.medias,
                          index: 0,
                          queueName: playlistData.title,
                        );
                      },
                      icon: Icon(
                        Icons.playlist_play,
                        size: 20.sp,
                      ),
                      label: Text(
                        '播放',
                        style: TextStyle(
                          fontSize: 16.sp,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: 25.w, vertical: 15.w),
                      ),
                    ),
                    SizedBox(height: 10.w),
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

class TabletPlaylist extends ConsumerStatefulWidget {
  final PlaylistData playlistData;
  const TabletPlaylist({
    super.key,
    required this.playlistData,
  });
  @override
  ConsumerState<TabletPlaylist> createState() => _TabletPlaylistState();
}

class _TabletPlaylistState extends ConsumerState<TabletPlaylist> {
  // 静态快照
  late List<MediaItem> _queueSnapshot;
  // 预计算后的扁平行数据：滚动时只做索引，不做map取值和bool计算
  late List<_TabletPlaylistRow> _rows;

  @override
  void initState() {
    super.initState();
    _recomputeRowsIfNeeded(force: true);
  }

  @override
  void didUpdateWidget(covariant TabletPlaylist oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 数据通常仅在重进页面后变化，这里仅在列表实例变化时重算
    _recomputeRowsIfNeeded(
      force: !identical(oldWidget.playlistData.medias, widget.playlistData.medias),
    );
  }

  void _recomputeRowsIfNeeded({required bool force}) {
    if (!force) return;

    _queueSnapshot = List<MediaItem>.unmodifiable(widget.playlistData.medias);
    _rows = List<_TabletPlaylistRow>.unmodifiable(
      List<_TabletPlaylistRow>.generate(
        _queueSnapshot.length,
        (i) {
          final media = _queueSnapshot[i];
          return _TabletPlaylistRow(
            index: i,
            media: media,
            isGrey: media.extras?['isGrey'] == true,
          );
        },
        growable: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 头部尺寸按屏幕宽度一次性计算，避免滚动时频繁进入LayoutBuilder
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final pageHorizontal = 60.w;
    final listHorizontal = 30.w;

    const totalFlex = 11.0; // 3:8
    final usableWidth =
        (viewportWidth - pageHorizontal * 2 - 30.w).clamp(0.0, double.infinity);
    final coverSide = (usableWidth * 3 / totalFlex).clamp(180.w, 320.w).toDouble();

    return CustomScrollView(
      // 固定行高列表
      cacheExtent: DesktopPlayList._rowExtent * 10,
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: 16.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: SliverToBoxAdapter(
            child: _TabletPlaylistHeader(
              playlistData: widget.playlistData,
              coverSide: coverSide,
              queueSnapshot: _queueSnapshot,
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 18.w)),
        if (_rows.isEmpty)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: listHorizontal),
            sliver: SliverToBoxAdapter(
              child: Text(
                '暂无歌单歌曲数据',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: listHorizontal),
            // 播放高亮监听放到子树
            sliver: _TabletPlaylistSongSliver(
              rows: _rows,
              queueSnapshot: _queueSnapshot,
              queueName: widget.playlistData.title,
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: 16.w)),
      ],
    );
  }
}

class _TabletPlaylistRow {
  final int index;
  final MediaItem media;
  final bool isGrey;

  const _TabletPlaylistRow({
    required this.index,
    required this.media,
    required this.isGrey,
  });
}

class _TabletPlaylistSongSliver extends ConsumerWidget {
  final List<_TabletPlaylistRow> rows;
  final List<MediaItem> queueSnapshot;
  final String queueName;

  const _TabletPlaylistSongSliver({
    required this.rows,
    required this.queueSnapshot,
    required this.queueName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeMediaId = ref.watch(mediaItemProvider.select((s) => s.value?.id));

    return SliverFixedExtentList(
      itemExtent: 68.w,
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final row = rows[index];
          return Padding(
            padding: EdgeInsets.only(top: 4.w),
            child: MediaItemWidget(
              mediaItem: row.media,
              isGrey: row.isGrey,
              isActive: row.media.id == activeMediaId,
              onTap: row.isGrey
                  ? null
                  : () => SnowfluffMusicHandler().updateQueue(
                        queueSnapshot,
                        index: row.index,
                        queueName: queueName,
                      ),
            ),
          );
        },
        childCount: rows.length,
        addRepaintBoundaries: true,
        addAutomaticKeepAlives: false,
      ),
    );
  }
}

class _TabletPlaylistHeader extends StatelessWidget {
  final PlaylistData playlistData;
  final double coverSide;
  final List<MediaItem> queueSnapshot;

  const _TabletPlaylistHeader({
    required this.playlistData,
    required this.coverSide,
    required this.queueSnapshot,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: coverSide,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: coverSide,
            height: coverSide,
            child: CachedImage(
              imageUrl: playlistData.coverUrl,
              borderRadius: 12.w,
              pWidth: 960,
              pHeight: 960,
            ),
          ),
          SizedBox(width: 30.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 10.w),
                Row(
                  children: [
                    if (playlistData.isPrivate) ...[
                      Icon(
                        Icons.lock,
                        size: 22.w,
                        color: Theme.of(context).hintColor,
                      ),
                      SizedBox(width: 8.w),
                    ],
                    Expanded(
                      child: Text(
                        playlistData.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 28.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10.w),
                Text(
                  playlistData.description.isEmpty ? '暂无描述' : playlistData.description,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: Theme.of(context).hintColor,
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: queueSnapshot.isEmpty
                      ? null
                      : () {
                          SnowfluffMusicHandler().updateQueue(
                            queueSnapshot,
                            index: 0,
                            queueName: playlistData.title,
                          );
                        },
                  icon: Icon(
                    Icons.playlist_play,
                    size: 20.sp,
                  ),
                  label: Text(
                    '播放',
                    style: TextStyle(fontSize: 16.sp),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 14.w),
                  ),
                ),
                SizedBox(height: 10.w),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MobilePlaylist extends ConsumerStatefulWidget {
  static const double _rowExtent = 58.0;
  final PlaylistData playlistData;

  const MobilePlaylist({super.key, required this.playlistData});

  @override
  ConsumerState<MobilePlaylist> createState() => _MobilePlaylistState();
}

class _MobilePlaylistState extends ConsumerState<MobilePlaylist> {
  late List<MediaItem> _queueSnapshot;
  late List<_MobilePlaylistRow> _rows;

  @override
  void initState() {
    super.initState();
    _recomputeRowsIfNeeded(force: true);
  }

  @override
  void didUpdateWidget(covariant MobilePlaylist oldWidget) {
    super.didUpdateWidget(oldWidget);
    _recomputeRowsIfNeeded(
      force: !identical(
        oldWidget.playlistData.medias,
        widget.playlistData.medias,
      ),
    );
  }

  void _recomputeRowsIfNeeded({required bool force}) {
    if (!force) return;

    _queueSnapshot = List<MediaItem>.unmodifiable(widget.playlistData.medias);
    _rows = List<_MobilePlaylistRow>.unmodifiable(
      List<_MobilePlaylistRow>.generate(_queueSnapshot.length, (i) {
        final media = _queueSnapshot[i];
        return _MobilePlaylistRow(
          index: i,
          media: media,
          isGrey: media.extras?['isGrey'] == true,
        );
      }, growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final horizontal = 14.w;
    final headerGap = 14.w;
    final coverSide = ((viewportWidth - horizontal * 2 - headerGap) * 0.30)
      .clamp(86.w, 116.w)
        .toDouble();

    return CustomScrollView(
      cacheExtent: MobilePlaylist._rowExtent.w * 12,
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: 2.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontal),
          sliver: SliverToBoxAdapter(
            child: _MobilePlaylistHeader(
              playlistData: widget.playlistData,
              coverSide: coverSide,
              queueSnapshot: _queueSnapshot,
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 12.w)),
        if (_rows.isEmpty)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: horizontal),
            sliver: SliverToBoxAdapter(
              child: Text(
                '暂无歌单歌曲数据',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: horizontal),
            sliver: _MobilePlaylistSongSliver(
              rows: _rows,
              queueSnapshot: _queueSnapshot,
              queueName: widget.playlistData.title,
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: 12.w)),
      ],
    );
  }
}

class _MobilePlaylistRow {
  final int index;
  final MediaItem media;
  final bool isGrey;

  const _MobilePlaylistRow({
    required this.index,
    required this.media,
    required this.isGrey,
  });
}

class _MobilePlaylistHeader extends StatelessWidget {
  final PlaylistData playlistData;
  final double coverSide;
  final List<MediaItem> queueSnapshot;

  const _MobilePlaylistHeader({
    required this.playlistData,
    required this.coverSide,
    required this.queueSnapshot,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: coverSide,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 10.w),
          SizedBox(
            width: coverSide,
            height: coverSide,
            child: Material(
              type: MaterialType.transparency,
              borderRadius: BorderRadius.circular(12.w),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: queueSnapshot.isEmpty
                    ? null
                    : () {
                        SnowfluffMusicHandler().updateQueue(
                          queueSnapshot,
                          index: 0,
                          queueName: playlistData.title,
                        );
                      },
                child: CachedImage(
                  imageUrl: playlistData.coverUrl,
                  borderRadius: 12.w,
                  pWidth: 240,
                  pHeight: 240,
                ),
              ),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (playlistData.isPrivate) ...[
                      Icon(
                        Icons.lock,
                        size: 16.w,
                        color: Theme.of(context).hintColor,
                      ),
                      SizedBox(width: 6.w),
                    ],
                    Expanded(
                      child: Text(
                        playlistData.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 3.w),
                Text(
                  '${queueSnapshot.length} Songs',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Theme.of(context).hintColor,
                  ),
                ),
                SizedBox(height: 6.w),
                _MobileDescriptionPreview(
                  description: playlistData.description,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileDescriptionPreview extends StatelessWidget {
  final String description;

  const _MobileDescriptionPreview({required this.description});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rawDescription = description.trim();
    final hasDescription = rawDescription.isNotEmpty;
    final previewText = hasDescription ? rawDescription : '暂无描述';
    final style = TextStyle(
      fontSize: 12.sp,
      color: theme.hintColor,
      height: 1.35,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: previewText, style: style),
          textDirection: Directionality.of(context),
          maxLines: 2,
        )..layout(maxWidth: constraints.maxWidth);

        final canShowDialog = hasDescription && painter.didExceedMaxLines;
        final textChild = Text(
          previewText,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: style,
        );

        if (!canShowDialog) return textChild;

        return Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () =>
                _showPlaylistDescriptionDialog(context, rawDescription),
            borderRadius: BorderRadius.circular(8.w),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 2.w),
              child: textChild,
            ),
          ),
        );
      },
    );
  }
}

class _MobilePlaylistSongSliver extends ConsumerWidget {
  final List<_MobilePlaylistRow> rows;
  final List<MediaItem> queueSnapshot;
  final String queueName;

  const _MobilePlaylistSongSliver({
    required this.rows,
    required this.queueSnapshot,
    required this.queueName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeMediaId = ref.watch(
      mediaItemProvider.select((s) => s.value?.id),
    );

    return SliverFixedExtentList(
      itemExtent: MobilePlaylist._rowExtent.w,
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final row = rows[index];
          return MobileMediaItem(
            index: row.index + 1,
            mediaItem: row.media,
            isGrey: row.isGrey,
            isActive: row.media.id == activeMediaId,
            onTap: row.isGrey
                ? null
                : () => SnowfluffMusicHandler().updateQueue(
                    queueSnapshot,
                    index: row.index,
                    queueName: queueName,
                  ),
          );
        },
        childCount: rows.length,
        addRepaintBoundaries: true,
        addAutomaticKeepAlives: false,
      ),
    );
  }
}

class MobileMediaItem extends StatelessWidget {
  final int index;
  final MediaItem mediaItem;
  final VoidCallback? onTap;
  final bool isGrey;
  final bool isActive;

  const MobileMediaItem({
    super.key,
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
              // SizedBox(width: 12.w),
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

Future<void> _showPlaylistDescriptionDialog(
  BuildContext context,
  String description,
) {
  final content = description.trim().isEmpty ? '暂无描述' : description.trim();
  final direction = Directionality.of(context);
  final screenSize = MediaQuery.sizeOf(context);
  final dialogWidth = (screenSize.width * 0.86).clamp(260.w, 420.w).toDouble();
  final contentMaxHeight = (screenSize.height * 0.50).clamp(180.w, 420.w).toDouble();
  final textStyle = TextStyle(fontSize: 14.sp, height: 1.45);
  final contentPainter = TextPainter(
    text: TextSpan(text: content, style: textStyle),
    textDirection: direction,
  )..layout(maxWidth: dialogWidth - 32.w);
  final needScroll = contentPainter.height > contentMaxHeight;

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '歌单介绍',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, _) {
      return SafeArea(
        child: Center(
          child: Material(
            color: Theme.of(ctx).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14.w),
            ),
            child: SizedBox(
              width: dialogWidth,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16.w, 16.w, 16.w, 14.w),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '歌单介绍',
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 12.w),
                    if (needScroll)
                      SizedBox(
                        height: contentMaxHeight,
                        child: Scrollbar(
                          child: SingleChildScrollView(
                            child: Text(content, style: textStyle),
                          ),
                        ),
                      )
                    else
                      Text(content, style: textStyle),
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

String _formatMobileDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
