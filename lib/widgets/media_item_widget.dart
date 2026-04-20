// 展示媒体源的组件

import 'package:snowfluff/widgets/cached_image.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class MediaItemWidget extends StatelessWidget {
  final MediaItem mediaItem;
  final VoidCallback? onTap;
  final bool isGrey; // 是否灰色歌曲
  final bool isActive; // 是否当前播放歌曲
  final Color? activeColor; // 当前播放歌曲的颜色
  const MediaItemWidget({
    super.key,
    required this.mediaItem,
    this.onTap,
    this.isGrey = false,
    this.isActive = false,
    this.activeColor
  });
  Color _resolveActiveColor(ThemeData theme) {
    if (activeColor != null) return activeColor!;
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Color.alphaBlend(
      scheme.primary.withValues(alpha: isDark ? 0.28 : 0.14),
      scheme.surface,
    );
  }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool effectiveActive = isActive && !isGrey; // 当前播放歌曲且不是灰色歌曲才高亮
    final Color disabledColor = Theme.of(context).disabledColor;
    final Color normalSubColor = Theme.of(context).hintColor;
    final Color resolvedActiveColor = _resolveActiveColor(theme);
    Widget cover = AspectRatio(
      aspectRatio: 1.0,
      child: CachedImage(
        imageUrl: mediaItem.artUri?.toString() ?? '',
        width: 42.w,
        height: 42.w,
        borderRadius: 7.w,
        pWidth: 224,
        pHeight: 224,
        ),
      );
    if (isGrey) {
      // 先去饱和度，再降低不透明度，看起来像是被灰色蒙住
      cover = ClipRRect(
        borderRadius: BorderRadius.circular(7.w),
        child: Opacity(
          opacity: 0.65,
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Colors.grey,
              BlendMode.saturation,
            ),
            child: cover,
          ),
        ),
      );
    }
    final bool disableHoverFeedback = isGrey || effectiveActive; // 灰色歌曲和当前播放歌曲都禁用hover反馈
    final ThemeData tileTheme = disableHoverFeedback
      ? theme.copyWith(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
      )
      : theme;
    return SizedBox(
      height: 64.w,
      child: Theme(
        data: tileTheme,
        child: Material(
          type: MaterialType.transparency,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.w),
          ),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: BoxDecoration(
              color: effectiveActive ? resolvedActiveColor : Colors.transparent, // 当前播放歌曲高亮
              borderRadius: BorderRadius.circular(10.w),
            ),
            child: InkWell(
              onTap: isGrey ? null : onTap,
              mouseCursor: isGrey ? SystemMouseCursors.basic : SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(10.w),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 42.w,
                      child: cover,
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            mediaItem.title,
                            style: TextStyle(
                              fontSize: 14.sp,
                              color: isGrey ? disabledColor : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 2.w),
                          Text(
                            mediaItem.artist ?? '',
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: isGrey ? disabledColor : normalSubColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      _formatDuration(mediaItem.duration!),
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: isGrey ? disabledColor : normalSubColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
