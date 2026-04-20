import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

const WidgetStatePropertyAll<Color> _kTransparentOverlay =
    WidgetStatePropertyAll<Color>(Colors.transparent);

class AlbumMediaItemWidget extends StatelessWidget {
  final MediaItem mediaItem;
  final VoidCallback? onTap;
  final bool isGrey; // 是否灰色歌曲
  final bool isActive; // 是否当前播放歌曲
  final Color? activeColor; // 当前播放歌曲的颜色
  const AlbumMediaItemWidget({
    super.key,
    required this.mediaItem, // 用extra的no值作为序号
    this.onTap,
    this.isGrey = false,
    this.isActive = false,
    this.activeColor
  });
  Color _resolveActiveColor(ThemeData theme, Color? custom) {
    if (custom != null) return custom;
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
    final normalSubColor = theme.hintColor;
    final trackNo = _trackNo(mediaItem);
    final durationText = _formatDuration(mediaItem.duration ?? Duration.zero);
    final radius = BorderRadius.circular(10.w);
    final resolvedActiveColor = _resolveActiveColor(theme, activeColor);
    return SizedBox(
      height: 42.w,
      child: Material(
        type: MaterialType.transparency,
        shape: RoundedRectangleBorder(borderRadius: radius),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            color: effectiveActive ? resolvedActiveColor : Colors.transparent,
            borderRadius: radius,
          ),
          child: InkWell(
            onTap: isGrey ? null : onTap,
            mouseCursor: isGrey
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            borderRadius: radius,
            splashFactory: (isGrey || effectiveActive)
                ? NoSplash.splashFactory
                : null,
            overlayColor: (isGrey || effectiveActive)
                ? _kTransparentOverlay
                : WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.pressed)) {
                      return normalSubColor.withValues(alpha: 0.18);
                    }
                    if (states.contains(WidgetState.hovered)) {
                      return normalSubColor.withValues(alpha: 0.10);
                    }
                    if (states.contains(WidgetState.focused)) {
                      return normalSubColor.withValues(alpha: 0.12);
                    }
                    return null;
                  }),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14.w),
              child: Row(
                children: [
                  SizedBox(
                    width: 42.w,
                    child: Text(
                      trackNo > 0 ? trackNo.toString() : '-',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: isGrey ? disabledColor : normalSubColor,
                      ),
                    ),
                  ),
                  SizedBox(width: 14.w),
                  Expanded(
                    child: Text(
                      mediaItem.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: isGrey ? disabledColor : null,
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Text(
                    durationText,
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
    );
  }
}

int _trackNo(MediaItem mediaItem) {
  final raw = mediaItem.extras?['no'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw) ?? 0;
  return 0;
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
