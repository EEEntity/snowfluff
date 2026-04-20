// 歌曲封面

import 'package:snowfluff/widgets/cached_image.dart';
import 'package:flutter/material.dart';

class AlbumView extends StatelessWidget {
  final String? imageUrl;
  final double? maxWidth; // 允许外部限制最大宽度
  final Key? animatedSwitcherKey; // 在PlayPage切换动画时保持状态
  const AlbumView({
    super.key,
    this.imageUrl,
    this.maxWidth,
    this.animatedSwitcherKey // 如果外部用AnimatedSwitcher，可以传入Key
  });
  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? 400, // 默认最大400
          maxHeight: maxWidth ?? 400 // 保持正方形
        ),
        child: AspectRatio(
          // 如果外部在AnimatedSwitcher里用，建议使用外部传入的key
          key: animatedSwitcherKey ?? const ValueKey('album_view_default'),
          aspectRatio: 1, // 强制1:1
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Container(
              color: Colors.transparent, //图片加载前透明
              child: _buildImageContent(),
            )
          )
        ),
      ),
    );
  }

  // 图片加载逻辑
  Widget _buildImageContent() {
    if (imageUrl == null || imageUrl!.isEmpty) {
      // 1.无URL时显示占位图标
      return const Icon(
        Icons.music_note,
        size: 100,
        color: Colors.white24,
      );
    }
    // 复用加上UA和Referer的CachedImage组件
    return CachedImage(
      imageUrl: imageUrl!,
      borderRadius: 30,
      pWidth: 640,
      pHeight: 640,
      fit: BoxFit.cover,
      placeholder: const SizedBox.shrink(), // 播放页有背景色，加载中保持透明
      errorWidget: const Icon(
        Icons.broken_image_outlined,
        size: 100,
        color: Colors.white24,
      ),
    );
  }
}
