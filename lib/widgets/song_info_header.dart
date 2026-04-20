// 歌曲标题/歌手组件

import 'package:snowfluff/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

class SongInfoHeader extends StatelessWidget {
  final String title;
  final List<String>? artists;
  final CrossAxisAlignment crossAxisAlignment;
  const SongInfoHeader({
    super.key,
    required this.title,
    this.artists,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });
  @override
  Widget build(BuildContext context) {
    // 检查是否有歌手数据
    final bool hasArtists = artists != null && artists!.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        // 歌曲标题：始终显示
        Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontSize: 20.sp,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (hasArtists) ...[
          SizedBox(height: 8.h), // 有歌手时才需要间距
          Text(
            artists!.join(" / "),
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14.sp,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        ]
      ],
    );
  }
}

class ArtistInfo {
  final int? id;
  final String name;

  const ArtistInfo({this.id, required this.name});
}

/// 带可点击歌手链接的歌曲标题/歌手组件，用于宽屏播放页
/// - 有 ID 的歌手：可点击跳转，桌面端 hover 时显示下划线 + pointer 光标
/// - 无 ID 的歌手：纯文本，不可点击
class SongInfoHeaderExtended extends StatelessWidget {
  final String title;
  final List<ArtistInfo>? artists;
  final CrossAxisAlignment crossAxisAlignment;

  const SongInfoHeaderExtended({
    super.key,
    required this.title,
    this.artists,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasArtists = artists != null && artists!.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontSize: 20.sp,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (hasArtists) ...[
          SizedBox(height: 8.h),
          _ArtistRow(
            artists: artists!,
            crossAxisAlignment: crossAxisAlignment,
          ),
        ],
      ],
    );
  }
}

class _ArtistRow extends StatelessWidget {
  final List<ArtistInfo> artists;
  final CrossAxisAlignment crossAxisAlignment;

  const _ArtistRow({required this.artists, required this.crossAxisAlignment});

  WrapAlignment get _wrapAlignment {
    if (crossAxisAlignment == CrossAxisAlignment.start) return WrapAlignment.start;
    if (crossAxisAlignment == CrossAxisAlignment.end) return WrapAlignment.end;
    return WrapAlignment.center;
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = [];
    for (int i = 0; i < artists.length; i++) {
      if (i > 0) {
        children.add(Text(
          ' / ',
          style: TextStyle(color: Colors.white70, fontSize: 14.sp),
        ));
      }
      final artist = artists[i];
      if (artist.id != null) {
        children.add(_ClickableArtist(artist: artist));
      } else {
        children.add(Text(
          artist.name,
          style: TextStyle(color: Colors.white70, fontSize: 14.sp),
        ));
      }
    }
    return Wrap(
      alignment: _wrapAlignment,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

class _ClickableArtist extends StatefulWidget {
  final ArtistInfo artist;

  const _ClickableArtist({required this.artist});

  @override
  State<_ClickableArtist> createState() => _ClickableArtistState();
}

class _ClickableArtistState extends State<_ClickableArtist> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => context.go('${AppRouter.artist}?id=${widget.artist.id}'),
        child: Text(
          widget.artist.name,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14.sp,
            decoration: _hovered ? TextDecoration.underline : TextDecoration.none,
            decorationColor: Colors.white70,
          ),
        ),
      ),
    );
  }
}
