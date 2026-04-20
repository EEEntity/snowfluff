// 搜索结果页面

import 'package:snowfluff/common/music_handler.dart';
import 'package:snowfluff/pages/provider.dart';
import 'package:snowfluff/pages/search/provider.dart';
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

class SearchPage extends ConsumerWidget {
  final String keywords;

  const SearchPage(this.keywords, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = DeviceConfig.layoutMode;
    final artistsAsync = ref.watch(artistsProvider(keywords));
    final albumsAsync = ref.watch(albumsProvider(keywords));
    final songsAsync = mode == LayoutMode.mobile
        ? ref.watch(songsProvider(keywords))
        : ref.watch(songsWithCoverProvider(keywords));
    final playlistsAsync = ref.watch(playlistsProvider(keywords));

    if (artistsAsync.isLoading ||
        albumsAsync.isLoading ||
        songsAsync.isLoading ||
        playlistsAsync.isLoading) {
      return const Center(child: LoadingIndicator());
    }

    if (artistsAsync.hasError ||
        albumsAsync.hasError ||
        songsAsync.hasError ||
        playlistsAsync.hasError) {
      return const Center(child: Text('Something search wrong...'));
    }

    final artists = artistsAsync.requireValue;
    final albums = albumsAsync.requireValue;
    final songs = songsAsync.requireValue;
    final playlists = playlistsAsync.requireValue;

    return switch(DeviceConfig.layoutMode) {
      LayoutMode.desktop => DesktopSearchPage(
          keywords: keywords,
          artists: artists,
          albums: albums,
          songs: songs,
          playlists: playlists,
        ),
      LayoutMode.tablet => TabletSearchPage(
          keywords: keywords,
          artistsAsync: artistsAsync,
          albumsAsync: albumsAsync,
          songsAsync: songsAsync,
          playlistsAsync: playlistsAsync,
        ),
      LayoutMode.mobile => MobileSearchPage(
          keywords: keywords,
          artists: artists,
          albums: albums,
          songs: songs,
          playlists: playlists,
        ),
    };
  }
}

class MobileSearchPage extends ConsumerStatefulWidget {
  static const double _songRowExtent = 58.0;
  static const double _entityRowExtent = 72.0;

  final String keywords;
  final List<SearchArtistCardData> artists;
  final List<SearchAlbumCardData> albums;
  final List<MediaItem> songs;
  final List<SearchPlaylistCardData> playlists;

  const MobileSearchPage({
    super.key,
    required this.keywords,
    required this.artists,
    required this.albums,
    required this.songs,
    required this.playlists,
  });

  @override
  ConsumerState<MobileSearchPage> createState() => _MobileSearchPageState();
}

class _MobileSearchPageState extends ConsumerState<MobileSearchPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final Set<int> _activatedTabs = <int>{0};
  bool _tabGestureLocked = false;

  late List<MediaItem> _queueSnapshot;
  late List<_MobileSearchSongRow> _songRows;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabInteraction);
    _recomputeData(force: true);
  }

  @override
  void didUpdateWidget(covariant MobileSearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final songsChanged =
        !identical(oldWidget.songs, widget.songs) ||
        oldWidget.songs.length != widget.songs.length;
    final keywordsChanged = oldWidget.keywords != widget.keywords;
    _recomputeData(force: songsChanged || keywordsChanged);
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
    _queueSnapshot = List<MediaItem>.unmodifiable(widget.songs);
    _songRows = List<_MobileSearchSongRow>.unmodifiable(
      List<_MobileSearchSongRow>.generate(_queueSnapshot.length, (i) {
        final media = _queueSnapshot[i];
        return _MobileSearchSongRow(
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
    final queueName = _buildSearchQueueName(widget.keywords);

    return Column(
      children: [
        SizedBox(height: 4.w),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontal),
          child: _MobileSearchTabBar(controller: _tabController),
        ),
        SizedBox(height: 8.w),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            dragStartBehavior: DragStartBehavior.down,
            physics: const _MobileSearchTabViewPhysics(
              parent: ClampingScrollPhysics(),
            ),
            children: [
              _DeferredMobileSearchTabBody(
                enabled: _activatedTabs.contains(0),
                pointerLocked: _tabGestureLocked,
                child: _MobileSearchSongTab(
                  rows: _songRows,
                  queueSnapshot: _queueSnapshot,
                  queueName: queueName,
                  horizontal: horizontal,
                ),
              ),
              _DeferredMobileSearchTabBody(
                enabled: _activatedTabs.contains(1),
                pointerLocked: _tabGestureLocked,
                child: _MobileSearchPlaylistTab(
                  playlists: widget.playlists,
                  horizontal: horizontal,
                ),
              ),
              _DeferredMobileSearchTabBody(
                enabled: _activatedTabs.contains(2),
                pointerLocked: _tabGestureLocked,
                child: _MobileSearchAlbumTab(
                  albums: widget.albums,
                  horizontal: horizontal,
                ),
              ),
              _DeferredMobileSearchTabBody(
                enabled: _activatedTabs.contains(3),
                pointerLocked: _tabGestureLocked,
                child: _MobileSearchArtistTab(
                  artists: widget.artists,
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

class _MobileSearchSongRow {
  final int index;
  final MediaItem media;
  final bool isGrey;

  const _MobileSearchSongRow({
    required this.index,
    required this.media,
    required this.isGrey,
  });
}

class _DeferredMobileSearchTabBody extends StatelessWidget {
  final bool enabled;
  final bool pointerLocked;
  final Widget child;

  const _DeferredMobileSearchTabBody({
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

class _MobileSearchTabBar extends StatelessWidget {
  final TabController controller;

  const _MobileSearchTabBar({required this.controller});

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
      indicator: _MobileSearchTabIndicator(
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
        Tab(text: '单曲'),
        Tab(text: '歌单'),
        Tab(text: '专辑'),
        Tab(text: '歌手'),
      ],
    );
  }
}

class _MobileSearchTabViewPhysics extends PageScrollPhysics {
  const _MobileSearchTabViewPhysics({super.parent});

  @override
  _MobileSearchTabViewPhysics applyTo(ScrollPhysics? ancestor) {
    return _MobileSearchTabViewPhysics(parent: buildParent(ancestor));
  }

  @override
  double get minFlingDistance => 3.0;

  @override
  double get minFlingVelocity => 40.0;

  @override
  double? get dragStartDistanceMotionThreshold => 0.6;
}

class _MobileSearchTabIndicator extends Decoration {
  final Color color;
  final double width;
  final double height;
  final double radius;

  const _MobileSearchTabIndicator({
    required this.color,
    required this.width,
    required this.height,
    required this.radius,
  });

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) {
    return _MobileSearchTabIndicatorPainter(this, onChanged);
  }
}

class _MobileSearchTabIndicatorPainter extends BoxPainter {
  final _MobileSearchTabIndicator decoration;

  _MobileSearchTabIndicatorPainter(this.decoration, super.onChanged);

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

class _MobileSearchSongTab extends StatelessWidget {
  final List<_MobileSearchSongRow> rows;
  final List<MediaItem> queueSnapshot;
  final String queueName;
  final double horizontal;

  const _MobileSearchSongTab({
    required this.rows,
    required this.queueSnapshot,
    required this.queueName,
    required this.horizontal,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return _MobileSearchEmptyState(horizontal: horizontal);
    }

    return CustomScrollView(
      cacheExtent: MobileSearchPage._songRowExtent * 8,
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: 2.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontal),
          sliver: _MobileSearchSongSliver(
            rows: rows,
            queueSnapshot: queueSnapshot,
            queueName: queueName,
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 12.w)),
      ],
    );
  }
}

class _MobileSearchSongSliver extends ConsumerWidget {
  final List<_MobileSearchSongRow> rows;
  final List<MediaItem> queueSnapshot;
  final String queueName;

  const _MobileSearchSongSliver({
    required this.rows,
    required this.queueSnapshot,
    required this.queueName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeMediaId = ref.watch(mediaItemProvider.select((s) => s.value?.id));

    return SliverFixedExtentList(
      itemExtent: MobileSearchPage._songRowExtent.w,
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final row = rows[index];
          return _MobileSearchSongItem(
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

class _MobileSearchSongItem extends StatelessWidget {
  final int index;
  final MediaItem mediaItem;
  final VoidCallback? onTap;
  final bool isGrey;
  final bool isActive;

  const _MobileSearchSongItem({
    required this.index,
    required this.mediaItem,
    this.onTap,
    required this.isGrey,
    required this.isActive,
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
          color: effectiveActive ? _resolveActiveColor(theme) : Colors.transparent,
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
                _formatSearchMobileDuration(mediaItem.duration ?? Duration.zero),
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

class _MobileSearchPlaylistTab extends StatelessWidget {
  final List<SearchPlaylistCardData> playlists;
  final double horizontal;

  const _MobileSearchPlaylistTab({required this.playlists, required this.horizontal});

  @override
  Widget build(BuildContext context) {
    if (playlists.isEmpty) {
      return _MobileSearchEmptyState(horizontal: horizontal);
    }

    return CustomScrollView(
      cacheExtent: MobileSearchPage._entityRowExtent * 8,
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: 2.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontal),
          sliver: SliverFixedExtentList(
            itemExtent: MobileSearchPage._entityRowExtent.w,
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final row = playlists[index];
                final title = row.title.trim().isEmpty ? '未知歌单' : row.title;
                return _MobileSearchCoverListItem(
                  imageUrl: row.coverUrl,
                  title: title,
                  subtitle: row.subtitle,
                  onTap: () => context.push(AppRouter.playlist, extra: row.id),
                );
              },
              childCount: playlists.length,
              addRepaintBoundaries: true,
              addAutomaticKeepAlives: false,
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 12.w)),
      ],
    );
  }
}

class _MobileSearchAlbumTab extends StatelessWidget {
  final List<SearchAlbumCardData> albums;
  final double horizontal;

  const _MobileSearchAlbumTab({required this.albums, required this.horizontal});

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return _MobileSearchEmptyState(horizontal: horizontal);
    }

    return CustomScrollView(
      cacheExtent: MobileSearchPage._entityRowExtent * 8,
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: 2.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontal),
          sliver: SliverFixedExtentList(
            itemExtent: MobileSearchPage._entityRowExtent.w,
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final row = albums[index];
                final title = row.name.trim().isEmpty ? '未知专辑' : row.name;
                final subtitle = row.artistNames.trim().isEmpty ? '未知艺人' : row.artistNames;
                return _MobileSearchCoverListItem(
                  imageUrl: row.coverUrl,
                  title: title,
                  subtitle: subtitle,
                  onTap: () => context.push(AppRouter.album, extra: row.id),
                );
              },
              childCount: albums.length,
              addRepaintBoundaries: true,
              addAutomaticKeepAlives: false,
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 12.w)),
      ],
    );
  }
}

class _MobileSearchArtistTab extends StatelessWidget {
  final List<SearchArtistCardData> artists;
  final double horizontal;

  const _MobileSearchArtistTab({required this.artists, required this.horizontal});

  @override
  Widget build(BuildContext context) {
    if (artists.isEmpty) {
      return _MobileSearchEmptyState(horizontal: horizontal);
    }

    return CustomScrollView(
      cacheExtent: MobileSearchPage._entityRowExtent * 8,
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: 2.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontal),
          sliver: SliverFixedExtentList(
            itemExtent: MobileSearchPage._entityRowExtent.w,
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final row = artists[index];
                final title = row.name.trim().isEmpty ? '未知歌手' : row.name;
                return _MobileSearchCoverListItem(
                  imageUrl: row.avatarUrl,
                  title: title,
                  subtitle: _formatMobileArtistSubtitle(row.subtitle),
                  onTap: () => context.push(AppRouter.artist, extra: row.id),
                );
              },
              childCount: artists.length,
              addRepaintBoundaries: true,
              addAutomaticKeepAlives: false,
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 12.w)),
      ],
    );
  }
}

class _MobileSearchCoverListItem extends StatelessWidget {
  final String imageUrl;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MobileSearchCoverListItem({
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

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
                  imageUrl: imageUrl,
                  width: 46.w,
                  height: 46.w,
                  fit: BoxFit.cover,
                  pWidth: 120,
                  pHeight: 120,
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
                      subtitle,
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

class _MobileSearchEmptyState extends StatelessWidget {
  final double horizontal;

  const _MobileSearchEmptyState({required this.horizontal});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: 8.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontal),
          sliver: SliverToBoxAdapter(
            child: Text(
              '空空如也',
              style: TextStyle(
                fontSize: 12.sp,
                color: Theme.of(context).hintColor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _buildSearchQueueName(String keywords) {
  final trimmed = keywords.trim();
  if (trimmed.isEmpty) return 'search-result';
  return 'search-result-$trimmed';
}

String _formatSearchMobileDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

String _formatMobileArtistSubtitle(String raw) {
  final compact = raw.replaceAll(' ', '');
  final match = RegExp(r'(\d+)首歌曲·(\d+)首专辑').firstMatch(compact);
  if (match != null) {
    final songCount = match.group(1) ?? '0';
    final albumCount = match.group(2) ?? '0';
    return '$albumCount 专辑 · $songCount 单曲';
  }

  if (raw.trim().isEmpty) return '0 专辑 · 0 单曲';
  return raw
      .replaceAll('首专辑', ' 专辑')
      .replaceAll('首歌曲', ' 单曲')
      .replaceAll('·', ' · ')
      .trim();
}

class DesktopSearchPage extends ConsumerStatefulWidget {
  final String keywords;
  final List<SearchArtistCardData> artists;
  final List<SearchAlbumCardData> albums;
  final List<MediaItem> songs;
  final List<SearchPlaylistCardData> playlists;

  static const int _songBatchSize = 8; // 分批渲染，降低瞬时构建压力
  static const int _playlistBatchSize = 6; // 歌单分批渲染
  static const double _loadMoreTriggerExtent = 900.0;
  static const double _scrollCacheExtent = 680.0;

  const DesktopSearchPage({
    super.key,
    required this.keywords,
    required this.artists,
    required this.albums,
    required this.songs,
    required this.playlists,
  });

  @override
  ConsumerState<DesktopSearchPage> createState() => _DesktopSearchPageState();
}

class _DesktopSearchPageState extends ConsumerState<DesktopSearchPage> {
  late final ScrollController _scrollController;

  int _visibleSongCount = 0;
  int _visiblePlaylistCount = 0;
  bool _isAppendingSongs = false;
  bool _isAppendingPlaylists = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _resetLazyState(force: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureViewportFilled();
    });
  }

  @override
  void didUpdateWidget(covariant DesktopSearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    final songsChanged = !identical(oldWidget.songs, widget.songs) ||
        oldWidget.songs.length != widget.songs.length;
    final playlistsChanged =
        !identical(oldWidget.playlists, widget.playlists) ||
            oldWidget.playlists.length != widget.playlists.length;
    final keywordChanged = oldWidget.keywords != widget.keywords;

    if (songsChanged || playlistsChanged || keywordChanged) {
      _resetLazyState(force: true);
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

  void _resetLazyState({required bool force}) {
    if (!force) return;
    _visibleSongCount = widget.songs.length < DesktopSearchPage._songBatchSize
        ? widget.songs.length
        : DesktopSearchPage._songBatchSize;
    _visiblePlaylistCount =
        widget.playlists.length < DesktopSearchPage._playlistBatchSize
            ? widget.playlists.length
            : DesktopSearchPage._playlistBatchSize;
  }

  bool get _hasMoreSongs => _visibleSongCount < widget.songs.length;

  bool get _hasMorePlaylists => _visiblePlaylistCount < widget.playlists.length;

  void _onScroll() {
    _tryAppendSongsIfNeeded();
    _tryAppendPlaylistsIfNeeded();
  }

  void _tryAppendSongsIfNeeded() {
    if (!_hasMoreSongs || _isAppendingSongs || !_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter > DesktopSearchPage._loadMoreTriggerExtent) return;
    _appendSongBatch();
  }

  void _tryAppendPlaylistsIfNeeded() {
    if (!_hasMorePlaylists || _isAppendingPlaylists || !_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter > DesktopSearchPage._loadMoreTriggerExtent) return;
    _appendPlaylistBatch();
  }

  void _appendSongBatch() {
    if (!_hasMoreSongs || _isAppendingSongs) return;
    _isAppendingSongs = true;

    final next = (_visibleSongCount + DesktopSearchPage._songBatchSize)
        .clamp(0, widget.songs.length)
        .toInt();

    if (next != _visibleSongCount && mounted) {
      setState(() {
        _visibleSongCount = next;
      });
    }

    _isAppendingSongs = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureViewportFilled();
    });
  }

  void _appendPlaylistBatch() {
    if (!_hasMorePlaylists || _isAppendingPlaylists) return;
    _isAppendingPlaylists = true;

    final next = (_visiblePlaylistCount + DesktopSearchPage._playlistBatchSize)
        .clamp(0, widget.playlists.length)
        .toInt();

    if (next != _visiblePlaylistCount && mounted) {
      setState(() {
        _visiblePlaylistCount = next;
      });
    }

    _isAppendingPlaylists = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureViewportFilled();
    });
  }

  void _ensureViewportFilled() {
    if (!_scrollController.hasClients) return;
    if (!_hasMoreSongs && !_hasMorePlaylists) return;
    if (_isAppendingSongs || _isAppendingPlaylists) return;

    if (_scrollController.position.maxScrollExtent <= 0) {
      if (_hasMoreSongs) {
        _appendSongBatch();
        return;
      }
      if (_hasMorePlaylists) {
        _appendPlaylistBatch();
        return;
      }
    } else {
      _tryAppendSongsIfNeeded();
      _tryAppendPlaylistsIfNeeded();
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeMediaId = ref.watch(mediaItemProvider.select((s) => s.value?.id));

    return CustomScrollView(
      controller: _scrollController,
      cacheExtent: DesktopSearchPage._scrollCacheExtent,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20.w, 20.w, 20.w, 0),
          sliver: SliverToBoxAdapter(
            child: _TopRowSection(
              artists: widget.artists,
              albums: widget.albums,
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 16.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          sliver: const SliverToBoxAdapter(child: _SurfaceTitle('歌曲')),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 10.w)),
        if (widget.songs.isEmpty)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            sliver: SliverToBoxAdapter(
              child: Text(
                '空空如也',
                style: TextStyle(fontSize: 12.sp, color: Theme.of(context).hintColor),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                const crossAxisCount = 4;
                final crossSpacing = 10.w;
                final mainSpacing = 8.w;
                const itemAspect = 3.4;

                final itemWidth = (constraints.crossAxisExtent -
                        (crossAxisCount - 1) * crossSpacing) /
                    crossAxisCount;
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
                      final media = widget.songs[index];
                      final isGrey = media.extras?['isGrey'] == true;
                      return _SongGridItem(
                        media: media,
                        isActive: media.id == activeMediaId,
                        onTap: isGrey
                            ? null
                            : () => SnowfluffMusicHandler().updateQueue(
                                  [media],
                                  index: 0,
                                  queueName: 'search-single-${media.id}',
                                ),
                      );
                    },
                    childCount: _visibleSongCount,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                  ),
                );
              },
            ),
          ),
        if (_hasMoreSongs)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 10.w),
              child: Center(
                child: SizedBox(
                  width: 18.w,
                  height: 18.w,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: 16.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          sliver: const SliverToBoxAdapter(child: _SurfaceTitle('歌单')),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 10.w)),
        if (widget.playlists.isEmpty)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            sliver: SliverToBoxAdapter(
              child: Text(
                '空空如也',
                style: TextStyle(fontSize: 12.sp, color: Theme.of(context).hintColor),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                const crossAxisCount = 6;
                final crossSpacing = 14.w;
                final mainSpacing = 14.w;

                final tileWidth = (constraints.crossAxisExtent -
                        (crossAxisCount - 1) * crossSpacing) /
                    crossAxisCount;
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
                      final playlist = widget.playlists[index];
                      return _PlaylistGridCard(
                        playlist: playlist,
                        onTap: () => context.push(AppRouter.playlist, extra: playlist.id),
                      );
                    },
                    childCount: _visiblePlaylistCount,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                  ),
                );
              },
            ),
          ),
        if (_hasMorePlaylists)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 10.w),
              child: Center(
                child: SizedBox(
                  width: 18.w,
                  height: 18.w,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: 20.w)),
      ],
    );
  }
}

class _TopRowSection extends StatelessWidget {
  final List<SearchArtistCardData> artists;
  final List<SearchAlbumCardData> albums;

  const _TopRowSection({
    required this.artists,
    required this.albums,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _SectionSurface(
            title: '艺人',
            child: _TopArtistsSection(items: artists),
          ),
        ),
        SizedBox(width: 14.w),
        Expanded(
          child: _SectionSurface(
            title: '专辑',
            child: _TopAlbumsSection(items: albums),
          ),
        ),
      ],
    );
  }
}

class _SectionSurface extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionSurface({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SurfaceTitle(title),
        SizedBox(height: 10.w),
        child,
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
      style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w700),
    );
  }
}

class _TopArtistsSection extends StatelessWidget {
  static const int _slotCount = 3;

  final List<SearchArtistCardData> items;

  const _TopArtistsSection({required this.items});

  @override
  Widget build(BuildContext context) {
    final list = items.take(_slotCount).toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 10.w;
        final slotWidth = (constraints.maxWidth - spacing * (_slotCount - 1)) / _slotCount;
        final cardHeight = slotWidth + 4.w + 18.w + 2.w + 14.w + 4.w;

        if (list.isEmpty) {
          return SizedBox(
            height: cardHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '空空如也',
                style: TextStyle(fontSize: 12.sp, color: Theme.of(context).hintColor),
              ),
            ),
          );
        }

        final children = <Widget>[];
        for (int i = 0; i < _slotCount; i++) {
          if (i > 0) children.add(SizedBox(width: spacing));
          children.add(
            Expanded(
              child: i < list.length
                  ? _TopArtistCard(
                    data: list[i],
                    onTap: () => context.push(AppRouter.artist, extra: list[i].id),
                  )
                  : const SizedBox.shrink(),
            ),
          );
        }

        return SizedBox(
          height: cardHeight,
          child: Row(children: children),
        );
      },
    );
  }
}

class _TopArtistCard extends StatefulWidget {
  final SearchArtistCardData data;
  final VoidCallback onTap;

  const _TopArtistCard({
    required this.data,
    required this.onTap,
  });

  @override
  State<_TopArtistCard> createState() => _TopArtistCardState();
}

class _TopArtistCardState extends State<_TopArtistCard> {
  bool _titleHovered = false;

  @override
  Widget build(BuildContext context) {
    final name = widget.data.name.isEmpty ? '未知艺人' : widget.data.name;
    final subtitle = widget.data.subtitle;

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
                      imageUrl: widget.data.avatarUrl,
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
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                decoration: _titleHovered ? TextDecoration.underline : TextDecoration.none,
                decorationThickness: 1.1,
              ),
            ),
          ),
        ),
        SizedBox(height: 2.w),
        Text(
          subtitle,
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

class _TopAlbumsSection extends StatelessWidget {
  static const int _slotCount = 3;

  final List<SearchAlbumCardData> items;

  const _TopAlbumsSection({required this.items});

  @override
  Widget build(BuildContext context) {
    final list = items.take(_slotCount).toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 10.w;
        final slotWidth = (constraints.maxWidth - spacing * (_slotCount - 1)) / _slotCount;
        final cardHeight = slotWidth + 4.w + 18.w + 2.w + 14.w + 4.w;

        if (list.isEmpty) {
          return SizedBox(
            height: cardHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '空空如也',
                style: TextStyle(fontSize: 12.sp, color: Theme.of(context).hintColor),
              ),
            ),
          );
        }

        final children = <Widget>[];
        for (int i = 0; i < _slotCount; i++) {
          if (i > 0) children.add(SizedBox(width: spacing));
          children.add(
            Expanded(
              child: i < list.length
                  ? _TopAlbumCard(
                      album: list[i],
                      onTap: () => context.push(AppRouter.album, extra: list[i].id),
                    )
                  : const SizedBox.shrink(),
            ),
          );
        }

        return SizedBox(
          height: cardHeight,
          child: Row(children: children),
        );
      },
    );
  }
}

class _TopAlbumCard extends StatefulWidget {
  final SearchAlbumCardData album;
  final VoidCallback onTap;

  const _TopAlbumCard({
    required this.album,
    required this.onTap,
  });

  @override
  State<_TopAlbumCard> createState() => _TopAlbumCardState();
}

class _TopAlbumCardState extends State<_TopAlbumCard> {
  bool _titleHovered = false;

  @override
  Widget build(BuildContext context) {
    final title = widget.album.name.isEmpty ? '未知专辑' : widget.album.name;
    final artists = widget.album.artistNames.trim().isEmpty ? '未知艺人' : widget.album.artistNames;

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
                      imageUrl: widget.album.coverUrl,
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
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                decoration: _titleHovered ? TextDecoration.underline : TextDecoration.none,
                decorationThickness: 1.1,
              ),
            ),
          ),
        ),
        SizedBox(height: 2.w),
        Text(
          artists,
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

class _SongGridItem extends StatefulWidget {
  final MediaItem media;
  final bool isActive;
  final VoidCallback? onTap;

  const _SongGridItem({
    required this.media,
    required this.isActive,
    this.onTap,
  });

  @override
  State<_SongGridItem> createState() => _SongGridItemState();
}

class _SongGridItemState extends State<_SongGridItem> {
  bool _hovered = false;

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
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10.w),
          onTap: enabled ? widget.onTap : null,
          child: Ink(
            decoration: BoxDecoration(
              color: widget.isActive
                  ? activeBg
                  : (_hovered && enabled ? hoverBg : Colors.transparent),
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

class _PlaylistGridCard extends StatefulWidget {
  final SearchPlaylistCardData playlist;
  final VoidCallback onTap;

  const _PlaylistGridCard({
    required this.playlist,
    required this.onTap,
  });

  @override
  State<_PlaylistGridCard> createState() => _PlaylistGridCardState();
}

class _PlaylistGridCardState extends State<_PlaylistGridCard> {
  bool _titleHovered = false;

  @override
  Widget build(BuildContext context) {
    final title = widget.playlist.title.isEmpty ? '未知歌单' : widget.playlist.title;

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
                      imageUrl: widget.playlist.coverUrl,
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
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                decoration: _titleHovered ? TextDecoration.underline : TextDecoration.none,
                decorationThickness: 1.1,
              ),
            ),
          ),
        ),
        SizedBox(height: 2.w),
        Text(
          widget.playlist.subtitle,
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

// 针对Android平板实现
class TabletSearchPage extends ConsumerWidget {
  final String keywords;
  final AsyncValue<List<SearchArtistCardData>> artistsAsync;
  final AsyncValue<List<SearchAlbumCardData>> albumsAsync;
  final AsyncValue<List<MediaItem>> songsAsync;
  final AsyncValue<List<SearchPlaylistCardData>> playlistsAsync;

  static const double _scrollCacheExtent = 760.0;

  const TabletSearchPage({
    super.key,
    required this.keywords,
    required this.artistsAsync,
    required this.albumsAsync,
    required this.songsAsync,
    required this.playlistsAsync,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeMediaId = ref.watch(mediaItemProvider.select((s) => s.value?.id));
    final pageHorizontal = 60.w;

    // provider返回后直接使用完整数据，不再做滚动分批加载
    final songs = songsAsync.value ?? const <MediaItem>[];
    final playlists = playlistsAsync.value ?? const <SearchPlaylistCardData>[];

    return CustomScrollView(
      cacheExtent: _scrollCacheExtent,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pageHorizontal, 18.w, pageHorizontal, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _SectionSurface(
                    title: '艺人',
                    child: _TabletTopArtistsSection(asyncItems: artistsAsync),
                  ),
                ),
                SizedBox(width: 14.w),
                Expanded(
                  child: _SectionSurface(
                    title: '专辑',
                    child: _TabletTopAlbumsSection(asyncItems: albumsAsync),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 16.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: const SliverToBoxAdapter(child: _SurfaceTitle('歌曲')),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 10.w)),
        ..._buildSongSlivers(
          context: context,
          pageHorizontal: pageHorizontal,
          activeMediaId: activeMediaId,
          songs: songs,
        ),
        SliverToBoxAdapter(child: SizedBox(height: 16.w)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: const SliverToBoxAdapter(child: _SurfaceTitle('歌单')),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 10.w)),
        ..._buildPlaylistSlivers(
          context: context,
          pageHorizontal: pageHorizontal,
          playlists: playlists,
        ),
        SliverToBoxAdapter(child: SizedBox(height: 20.w)),
      ],
    );
  }

  List<Widget> _buildSongSlivers({
    required BuildContext context,
    required double pageHorizontal,
    required String? activeMediaId,
    required List<MediaItem> songs,
  }) {
    if (songsAsync.isLoading && !songsAsync.hasValue) {
      return <Widget>[
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: SliverToBoxAdapter(
            child: _SectionLoadingPlaceholder(height: 120.w),
          ),
        ),
      ];
    }

    if (songsAsync.hasError && !songsAsync.hasValue) {
      return <Widget>[
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: SliverToBoxAdapter(
            child: _SectionHintText('歌曲加载失败'),
          ),
        ),
      ];
    }

    if (songs.isEmpty) {
      return <Widget>[
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: SliverToBoxAdapter(
            child: _SectionHintText('空空如也'),
          ),
        ),
      ];
    }

    return <Widget>[
      SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) {
            const crossAxisCount = 4;
            final crossSpacing = 10.w;
            final mainSpacing = 8.w;
            const itemAspect = 3.4;

            final itemWidth =
                (constraints.crossAxisExtent - (crossAxisCount - 1) * crossSpacing) /
                    crossAxisCount;
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
                  final media = songs[index];
                  final isGrey = media.extras?['isGrey'] == true;

                  return _TabletSongGridItem(
                    media: media,
                    isActive: media.id == activeMediaId,
                    onTap: isGrey
                        ? null
                        : () => SnowfluffMusicHandler().updateQueue(
                              <MediaItem>[media],
                              index: 0,
                              queueName: 'search-single-${media.id}',
                            ),
                  );
                },
                childCount: songs.length,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
              ),
            );
          },
        ),
      ),
    ];
  }

  List<Widget> _buildPlaylistSlivers({
    required BuildContext context,
    required double pageHorizontal,
    required List<SearchPlaylistCardData> playlists,
  }) {
    if (playlistsAsync.isLoading && !playlistsAsync.hasValue) {
      return <Widget>[
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: SliverToBoxAdapter(
            child: _SectionLoadingPlaceholder(height: 140.w),
          ),
        ),
      ];
    }

    if (playlistsAsync.hasError && !playlistsAsync.hasValue) {
      return <Widget>[
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: SliverToBoxAdapter(
            child: _SectionHintText('歌单加载失败'),
          ),
        ),
      ];
    }

    if (playlists.isEmpty) {
      return <Widget>[
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
          sliver: SliverToBoxAdapter(
            child: _SectionHintText('空空如也'),
          ),
        ),
      ];
    }

    return <Widget>[
      SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: pageHorizontal),
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) {
            const crossAxisCount = 6;
            final crossSpacing = 14.w;
            final mainSpacing = 14.w;

            final tileWidth =
                (constraints.crossAxisExtent - (crossAxisCount - 1) * crossSpacing) /
                    crossAxisCount;
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
                  final playlist = playlists[index];
                  return _TabletPlaylistGridCard(
                    playlist: playlist,
                    onTap: () => context.push(AppRouter.playlist, extra: playlist.id),
                  );
                },
                childCount: playlists.length,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
              ),
            );
          },
        ),
      ),
    ];
  }
}

class _TabletTopArtistsSection extends StatelessWidget {
  static const int _slotCount = 3;
  final AsyncValue<List<SearchArtistCardData>> asyncItems;
  const _TabletTopArtistsSection({required this.asyncItems});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 10.w;
        final slotWidth = (constraints.maxWidth - spacing * (_slotCount - 1)) / _slotCount;
        final cardHeight = slotWidth + 4.w + 18.w + 2.w + 14.w + 4.w;
        if (asyncItems.isLoading && !asyncItems.hasValue) {
          return _SectionLoadingPlaceholder(height: cardHeight);
        }

        if (asyncItems.hasError && !asyncItems.hasValue) {
          return SizedBox(
            height: cardHeight,
            child: const Align(
              alignment: Alignment.centerLeft,
              child: _SectionHintText('艺人加载失败'),
            ),
          );
        }

        final list = (asyncItems.value ?? const <SearchArtistCardData>[])
            .take(_slotCount)
            .toList(growable: false);

        if (list.isEmpty) {
          return SizedBox(
            height: cardHeight,
            child: const Align(
              alignment: Alignment.centerLeft,
              child: _SectionHintText('空空如也'),
            ),
          );
        }

        final children = <Widget>[];
        for (int i = 0; i < _slotCount; i++) {
          if (i > 0) children.add(SizedBox(width: spacing));
          children.add(
            Expanded(
              child: i < list.length
                  ? _TabletTopArtistCard(
                      data: list[i],
                      onTap: () => context.push(AppRouter.artist, extra: list[i].id),
                    )
                  : const SizedBox.shrink(),
            ),
          );
        }

        return SizedBox(
          height: cardHeight,
          child: Row(children: children),
        );
      },
    );
  }
}

class _TabletTopAlbumsSection extends StatelessWidget {
  static const int _slotCount = 3;

  final AsyncValue<List<SearchAlbumCardData>> asyncItems;

  const _TabletTopAlbumsSection({required this.asyncItems});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 10.w;
        final slotWidth = (constraints.maxWidth - spacing * (_slotCount - 1)) / _slotCount;
        final cardHeight = slotWidth + 4.w + 18.w + 2.w + 14.w + 4.w;

        if (asyncItems.isLoading && !asyncItems.hasValue) {
          return _SectionLoadingPlaceholder(height: cardHeight);
        }

        if (asyncItems.hasError && !asyncItems.hasValue) {
          return SizedBox(
            height: cardHeight,
            child: const Align(
              alignment: Alignment.centerLeft,
              child: _SectionHintText('专辑加载失败'),
            ),
          );
        }

        final list = (asyncItems.value ?? const <SearchAlbumCardData>[])
            .take(_slotCount)
            .toList(growable: false);

        if (list.isEmpty) {
          return SizedBox(
            height: cardHeight,
            child: const Align(
              alignment: Alignment.centerLeft,
              child: _SectionHintText('空空如也'),
            ),
          );
        }

        final children = <Widget>[];
        for (int i = 0; i < _slotCount; i++) {
          if (i > 0) children.add(SizedBox(width: spacing));
          children.add(
            Expanded(
              child: i < list.length
                  ? _TabletTopAlbumCard(
                      album: list[i],
                      onTap: () => context.push(AppRouter.album, extra: list[i].id),
                    )
                  : const SizedBox.shrink(),
            ),
          );
        }

        return SizedBox(
          height: cardHeight,
          child: Row(children: children),
        );
      },
    );
  }
}

class _TabletTopArtistCard extends StatelessWidget {
  final SearchArtistCardData data;
  final VoidCallback onTap;

  const _TabletTopArtistCard({
    required this.data,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = data.name.isEmpty ? '未知艺人' : data.name;
    final subtitle = data.subtitle;

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
                    imageUrl: data.avatarUrl,
                    fit: BoxFit.cover,
                    pWidth: 384,
                    pHeight: 384,
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: 4.w),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 2.w),
        Text(
          subtitle,
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

class _TabletTopAlbumCard extends StatelessWidget {
  final SearchAlbumCardData album;
  final VoidCallback onTap;

  const _TabletTopAlbumCard({
    required this.album,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = album.name.isEmpty ? '未知专辑' : album.name;
    final artists = album.artistNames.trim().isEmpty ? '未知艺人' : album.artistNames;

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
                    imageUrl: album.coverUrl,
                    fit: BoxFit.cover,
                    pWidth: 384,
                    pHeight: 384,
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: 4.w),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 2.w),
        Text(
          artists,
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

class _TabletSongGridItem extends StatelessWidget {
  final MediaItem media;
  final bool isActive;
  final VoidCallback? onTap;

  const _TabletSongGridItem({
    required this.media,
    required this.isActive,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isGrey = media.extras?['isGrey'] == true;
    final enabled = !isGrey && onTap != null;
    final hintColor = Theme.of(context).hintColor;
    final disabledColor = Theme.of(context).disabledColor;
    final activeBg = Theme.of(context).colorScheme.primary.withValues(alpha: 0.14);

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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10.w),
        onTap: enabled ? onTap : null,
        child: Ink(
          decoration: BoxDecoration(
            color: isActive ? activeBg : Colors.transparent,
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
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
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
    );
  }
}

class _TabletPlaylistGridCard extends StatelessWidget {
  final SearchPlaylistCardData playlist;
  final VoidCallback onTap;

  const _TabletPlaylistGridCard({
    required this.playlist,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = playlist.title.isEmpty ? '未知歌单' : playlist.title;

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
                    imageUrl: playlist.coverUrl,
                    fit: BoxFit.cover,
                    pWidth: 384,
                    pHeight: 384,
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: 4.w),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 2.w),
        Text(
          playlist.subtitle,
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

class _SectionLoadingPlaceholder extends StatelessWidget {
  final double height;

  const _SectionLoadingPlaceholder({required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _SectionHintText extends StatelessWidget {
  final String text;

  const _SectionHintText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12.sp,
        color: Theme.of(context).hintColor,
      ),
    );
  }
}
