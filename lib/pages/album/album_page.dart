import 'package:snowfluff/common/music_handler.dart';
import 'package:snowfluff/pages/album/provider.dart';
import 'package:snowfluff/pages/provider.dart';
import 'package:snowfluff/utils/device_config.dart';
import 'package:snowfluff/widgets/album_media_item_widget.dart';
import 'package:snowfluff/widgets/cached_image.dart';
import 'package:snowfluff/widgets/loading_indicator.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class AlbumPage extends ConsumerWidget {
  final int id;
  const AlbumPage(this.id, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final album = ref.watch(albumDetailProvider(id));
    return album.when(
      data: (details) => switch (DeviceConfig.layoutMode) {
          LayoutMode.desktop => DesktopAlbumPage(albumData: details),
          LayoutMode.tablet => TabletAlbumPage(albumData: details),
          LayoutMode.mobile => MobileAlbumPage(albumData: details),
      },
      loading: () => const Center(child: LoadingIndicator()),
      error: (_, _) => const Center(child: Text('Something album wrong...')),
    );
  }
}

class DesktopAlbumPage extends ConsumerStatefulWidget {
  final AlbumData albumData;
  const DesktopAlbumPage({
    super.key,
    required this.albumData,
  });

  @override
  ConsumerState<DesktopAlbumPage> createState() => _DesktopAlbumPageState();
}

class _DesktopAlbumPageState extends ConsumerState<DesktopAlbumPage> {
  late List<_AlbumRow> _rows;
  late List<MediaItem> _queueSnapshot;

  @override
  void initState() {
    super.initState();
    _recomputeRowsIfNeeded(force: true);
  }

  @override
  void didUpdateWidget(covariant DesktopAlbumPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _recomputeRowsIfNeeded(
      force: !identical(oldWidget.albumData.medias, widget.albumData.medias),
    );
  }

  void _recomputeRowsIfNeeded({required bool force}) {
    if (!force) return;
    _queueSnapshot = List<MediaItem>.unmodifiable(widget.albumData.medias);
    final hasMultipleDiscs = _hasMultipleDiscs(_queueSnapshot);
    _rows = _buildAlbumRows(_queueSnapshot, hasMultipleDiscs);
  }

  @override
  Widget build(BuildContext context) {
    final activeMediaId = ref.watch(mediaItemProvider.select((s) => s.value?.id));

    return CustomScrollView(
      cacheExtent: 56.0 * 8, // 可能需要调整
      slivers: [
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: 60.w, vertical: 20.w),
          sliver: SliverToBoxAdapter(
            child: _AlbumHeader(albumData: widget.albumData),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 24.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: 30.w),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final row = _rows[index];
                if (row.isHeader) {
                  return Padding(
                    padding: EdgeInsets.fromLTRB(30.w, 14.w, 2.w, 8.w),
                    child: Text(
                      row.discLabel,
                      style: TextStyle(
                        fontSize: 17.sp,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  );
                }

                final media = _queueSnapshot[row.mediaIndex];
                final isGrey = media.extras?['isGrey'] == true;
                return Padding(
                  padding: EdgeInsets.only(bottom: 4.w),
                  child: _AlbumMediaRowTile(
                    media: media,
                    isGrey: isGrey,
                    isActive: media.id == activeMediaId,
                    mediaIndex: row.mediaIndex,
                    queueName: widget.albumData.name,
                    queueSnapshot: _queueSnapshot,
                  ),
                );
              },
              childCount: _rows.length,
              addRepaintBoundaries: true,
              addAutomaticKeepAlives: false,
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 16.w)),
        SliverToBoxAdapter(
          child: Center(
            child: Text(
              _formatPublishDateCn(widget.albumData.publishTime),
              style: TextStyle(
                fontSize: 12.sp,
                color: Theme.of(context).hintColor,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 20.w)),
      ],
    );
  }
}

class _AlbumMediaRowTile extends StatelessWidget {
  final MediaItem media;
  final bool isGrey;
  final bool isActive;
  final int mediaIndex;
  final String queueName;
  final List<MediaItem> queueSnapshot;

  const _AlbumMediaRowTile({
    required this.media,
    required this.isGrey,
    required this.isActive,
    required this.mediaIndex,
    required this.queueName,
    required this.queueSnapshot,
  });

  @override
  Widget build(BuildContext context) {
    return AlbumMediaItemWidget(
      mediaItem: media,
      isGrey: isGrey,
      isActive: isActive,
      onTap: isGrey
          ? null
          : () => SnowfluffMusicHandler().updateQueue(
                    queueSnapshot,
                    index: mediaIndex,
                    queueName: queueName,
                  ),
    );
  }
}

class _AlbumHeader extends StatelessWidget {
  final AlbumData albumData;
  const _AlbumHeader({
    required this.albumData,
  });
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const totalFlex = 11; // 3:8
        final coverSide = (constraints.maxWidth - 40.w) * 3 / totalFlex;
        final artistText = albumData.artists.isEmpty
            ? '未知艺术家'
            : albumData.artists.join(' / ');
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: AspectRatio(
                aspectRatio: 1,
                child: CachedImage(
                  imageUrl: albumData.coverUrl,
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            albumData.name,
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
                    SizedBox(height: 10.w),
                    Text(
                      artistText,
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: Theme.of(context).hintColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 12.w),
                    Text(
                      albumData.description.isEmpty ? '暂无描述' : albumData.description,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Theme.of(context).hintColor,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: albumData.medias.isEmpty
                          ? null
                          : () {
                              SnowfluffMusicHandler().updateQueue(
                                albumData.medias,
                                index: 0,
                                queueName: albumData.name,
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

class _AlbumRow {
  final bool isHeader;
  final String discLabel;
  final int mediaIndex;
  const _AlbumRow.header(this.discLabel)
      : isHeader = true,
        mediaIndex = -1;
  const _AlbumRow.item(this.mediaIndex)
      : isHeader = false,
        discLabel = '';
}

List<_AlbumRow> _buildAlbumRows(List<MediaItem> medias, bool hasMultipleDiscs) {
  if (medias.isEmpty) return const <_AlbumRow>[];
  if (!hasMultipleDiscs) {
    return List<_AlbumRow>.generate(
      medias.length,
      (i) => _AlbumRow.item(i),
      growable: false,
    );
  }
  final out = <_AlbumRow>[];
  String prevDiscKey = '';
  for (int i = 0; i < medias.length; i++) {
    final disc = _discOf(medias[i]);
    if (i == 0 || disc != prevDiscKey) {
      out.add(_AlbumRow.header(disc.isEmpty ? '未知碟片' : 'Disc $disc'));
      prevDiscKey = disc;
    }
    out.add(_AlbumRow.item(i));
  }
  return out;
}

bool _hasMultipleDiscs(List<MediaItem> medias) {
  if (medias.length < 2) return false;
  final first = _discOf(medias.first);
  for (int i = 1; i < medias.length; i++) {
    if (_discOf(medias[i]) != first) return true;
  }
  return false;
}

String _discOf(MediaItem media) {
  final value = media.extras?['disc'];
  return (value?.toString() ?? '').trim();
}

String _formatPublishDateCn(int timestampMs) {
  if (timestampMs <= 0) return '发布时间未知';
  final dtUtc8 = DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true)
      .add(const Duration(hours: 8));
  return '发行于 ${dtUtc8.year}年${dtUtc8.month}月${dtUtc8.day}日';
}

class TabletAlbumPage extends ConsumerStatefulWidget {
  final AlbumData albumData;
  const TabletAlbumPage({
    super.key,
    required this.albumData,
  });
  @override
  ConsumerState<TabletAlbumPage> createState() => _TabletAlbumPageState();
}

class _TabletAlbumPageState extends ConsumerState<TabletAlbumPage> {
  // 静态快照：页面生命周期内不再变，避免滚动时反复访问可变数据结构
  late List<MediaItem> _queueSnapshot;
  // 预计算后的"标题行+歌曲行"扁平结构，滚动时只做O(1)索引
  late List<_AlbumRow> _rows;
  @override
  void initState() {
    super.initState();
    _recomputeRowsIfNeeded(force: true);
  }
  @override
  void didUpdateWidget(covariant TabletAlbumPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 数据只有重进页面才可能变化；仅在列表实例变化时重算
    _recomputeRowsIfNeeded(
      force: !identical(oldWidget.albumData.medias, widget.albumData.medias),
    );
  }
  void _recomputeRowsIfNeeded({required bool force}) {
    if (!force) return;
    _queueSnapshot = List<MediaItem>.unmodifiable(widget.albumData.medias);
    final hasMultipleDiscs = _hasMultipleDiscs(_queueSnapshot);
    _rows = List<_AlbumRow>.unmodifiable(
      _buildAlbumRows(_queueSnapshot, hasMultipleDiscs),
    );
  }
  @override
  Widget build(BuildContext context) {
    // 宽度只按屏幕算一次，不在滚动过程中走SliverLayoutBuilder
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final pageHorizontal = 60.w;
    final listHorizontal = 30.w;
    // 3:8的封面/信息，clamp防止极端尺寸抖动
    const totalFlex = 11.0;
    final usableWidth = (viewportWidth - pageHorizontal * 2 - 34.w).clamp(0.0, double.infinity);
    final coverSide = (usableWidth * 3 / totalFlex).clamp(180.w, 320.w).toDouble();
    return CustomScrollView(
      // 固定行高42.w*10预取
      cacheExtent: 42.w * 10,
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: 16.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: SliverToBoxAdapter(
            child: _TabletAlbumHeader(
              albumData: widget.albumData,
              coverSide: coverSide,
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 18.w)),
        if (_rows.isEmpty)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: listHorizontal),
            sliver: SliverToBoxAdapter(
              child: Text(
                '暂无专辑歌曲数据',
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
            // 播放中高亮监听放在歌曲列表子树，避免频繁重建
            sliver: _TabletAlbumSongSliver(
              rows: _rows,
              queueSnapshot: _queueSnapshot,
              queueName: widget.albumData.name,
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: 14.w)),
        SliverToBoxAdapter(
          child: Center(
            child: Text(
              _formatPublishDateCn(widget.albumData.publishTime),
              style: TextStyle(
                fontSize: 12.sp,
                color: Theme.of(context).hintColor,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 16.w)),
      ],
    );
  }
}

class _TabletAlbumSongSliver extends ConsumerWidget {
  final List<_AlbumRow> rows;
  final List<MediaItem> queueSnapshot;
  final String queueName;
  const _TabletAlbumSongSliver({
    required this.rows,
    required this.queueSnapshot,
    required this.queueName,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeMediaId = ref.watch(
      mediaItemProvider.select((s) => s.value?.id),
    );
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final row = rows[index];
          if (row.isHeader) {
            return Padding(
              padding: EdgeInsets.fromLTRB(24.w, 12.w, 2.w, 8.w),
              child: Text(
                row.discLabel,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            );
          }
          final media = queueSnapshot[row.mediaIndex];
          final isGrey = media.extras?['isGrey'] == true;
          return Padding(
            padding: EdgeInsets.only(bottom: 4.w),
            child: _AlbumMediaRowTile(
              media: media,
              isGrey: isGrey,
              isActive: media.id == activeMediaId,
              mediaIndex: row.mediaIndex,
              queueName: queueName,
              queueSnapshot: queueSnapshot,
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

class _TabletAlbumHeader extends StatelessWidget {
  final AlbumData albumData;
  final double coverSide;
  const _TabletAlbumHeader({
    required this.albumData,
    required this.coverSide,
  });
  @override
  Widget build(BuildContext context) {
    final artistText = albumData.artists.isEmpty ? '未知艺术家' : albumData.artists.join(' / ');
    return SizedBox(
      height: coverSide,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: coverSide,
            height: coverSide,
            child: CachedImage(
              imageUrl: albumData.coverUrl,
              borderRadius: 12.w,
              pWidth: 960,
              pHeight: 960,
            ),
          ),
          SizedBox(width: 34.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 10.w),
                Text(
                  albumData.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 28.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 8.w),
                Text(
                  artistText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: Theme.of(context).hintColor,
                  ),
                ),
                SizedBox(height: 10.w),
                Text(
                  albumData.description.isEmpty ? '暂无描述' : albumData.description,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Theme.of(context).hintColor,
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: albumData.medias.isEmpty
                      ? null
                      : () {
                          SnowfluffMusicHandler().updateQueue(
                            albumData.medias,
                            index: 0,
                            queueName: albumData.name,
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

class MobileAlbumPage extends ConsumerStatefulWidget {
  static const double _rowExtent = 52.0;
  final AlbumData albumData;

  const MobileAlbumPage({
    super.key,
    required this.albumData,
  });

  @override
  ConsumerState<MobileAlbumPage> createState() => _MobileAlbumPageState();
}

class _MobileAlbumPageState extends ConsumerState<MobileAlbumPage> {
  late List<MediaItem> _queueSnapshot;
  late List<_MobileAlbumRow> _rows;

  @override
  void initState() {
    super.initState();
    _recomputeRowsIfNeeded(force: true);
  }

  @override
  void didUpdateWidget(covariant MobileAlbumPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _recomputeRowsIfNeeded(
      force: !identical(oldWidget.albumData.medias, widget.albumData.medias),
    );
  }

  void _recomputeRowsIfNeeded({required bool force}) {
    if (!force) return;

    _queueSnapshot = List<MediaItem>.unmodifiable(widget.albumData.medias);
    final hasMultipleDiscs = _hasMultipleDiscs(_queueSnapshot);
    final baseRows = _buildAlbumRows(_queueSnapshot, hasMultipleDiscs);

    final out = <_MobileAlbumRow>[];
    int trackNo = 0;
    for (final row in baseRows) {
      if (row.isHeader) {
        out.add(_MobileAlbumRow.header(row.discLabel));
        trackNo = 0;
        continue;
      }
      trackNo += 1;
      out.add(_MobileAlbumRow.item(mediaIndex: row.mediaIndex, trackNo: trackNo));
    }

    _rows = List<_MobileAlbumRow>.unmodifiable(out);
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
      cacheExtent: MobileAlbumPage._rowExtent.w * 12,
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: 2.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontal),
          sliver: SliverToBoxAdapter(
            child: _MobileAlbumHeader(
              albumData: widget.albumData,
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
                '暂无专辑歌曲数据',
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
            sliver: _MobileAlbumSongSliver(
              rows: _rows,
              queueSnapshot: _queueSnapshot,
              queueName: widget.albumData.name,
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: 12.w)),
      ],
    );
  }
}

class _MobileAlbumRow {
  final bool isHeader;
  final String discLabel;
  final int mediaIndex;
  final int trackNo;

  const _MobileAlbumRow.header(this.discLabel)
      : isHeader = true,
        mediaIndex = -1,
        trackNo = -1;

  const _MobileAlbumRow.item({
    required this.mediaIndex,
    required this.trackNo,
  }) : isHeader = false,
       discLabel = '';
}

class _MobileAlbumHeader extends StatelessWidget {
  final AlbumData albumData;
  final double coverSide;
  final List<MediaItem> queueSnapshot;

  const _MobileAlbumHeader({
    required this.albumData,
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
                          queueName: albumData.name,
                        );
                      },
                child: CachedImage(
                  imageUrl: albumData.coverUrl,
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
                Text(
                  albumData.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                  ),
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
                _MobileAlbumDescriptionPreview(
                  description: albumData.description,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileAlbumDescriptionPreview extends StatelessWidget {
  final String description;

  const _MobileAlbumDescriptionPreview({required this.description});

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
            onTap: () => _showAlbumDescriptionDialog(context, rawDescription),
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

class _MobileAlbumSongSliver extends ConsumerWidget {
  final List<_MobileAlbumRow> rows;
  final List<MediaItem> queueSnapshot;
  final String queueName;

  const _MobileAlbumSongSliver({
    required this.rows,
    required this.queueSnapshot,
    required this.queueName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeMediaId = ref.watch(
      mediaItemProvider.select((s) => s.value?.id),
    );

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final row = rows[index];
          if (row.isHeader) {
            return Text(
              row.discLabel,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            );
          }

          final media = queueSnapshot[row.mediaIndex];
          final isGrey = media.extras?['isGrey'] == true;
          return SizedBox(
            height: MobileAlbumPage._rowExtent.w,
            child: MobileAlbumMediaItem(
              index: row.trackNo,
              mediaItem: media,
              isGrey: isGrey,
              isActive: media.id == activeMediaId,
              onTap: isGrey
                  ? null
                  : () => SnowfluffMusicHandler().updateQueue(
                        queueSnapshot,
                        index: row.mediaIndex,
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

class MobileAlbumMediaItem extends StatelessWidget {
  final int index;
  final MediaItem mediaItem;
  final VoidCallback? onTap;
  final bool isGrey;
  final bool isActive;

  const MobileAlbumMediaItem({
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
                child: Text(
                  mediaItem.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: isGrey ? disabledColor : null,
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                _formatMobileAlbumDuration(mediaItem.duration ?? Duration.zero),
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

Future<void> _showAlbumDescriptionDialog(
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
    barrierLabel: '专辑介绍',
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
                      '专辑介绍',
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

String _formatMobileAlbumDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
