import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class CachedImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final double borderRadius;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final int pWidth;
  final int pHeight;
  final bool enableFade;
  final bool useOldImageOnUrlChange;
  final String? cacheKey;
  final Clip clipBehavior;
  const CachedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.borderRadius = 8.0,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.pWidth = 160, // 默认减少尺寸，节省内存和流量
    this.pHeight = 160,
    this.enableFade = false,
    this.useOldImageOnUrlChange = true,
    this.cacheKey,
    this.clipBehavior = Clip.antiAlias, // 减少圆角锯齿
  });
  // 播放器
  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return _defaultPlaceholder(context);
    }
    Widget image = _buildCachedNetworkImage();
    return borderRadius > 0
      ? ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        clipBehavior: clipBehavior,
        child: image,
      )
      : image;
  }

  Widget _buildCachedNetworkImage() {
    final String finalUrl = _normalizeUrl(imageUrl);
    final String? resolvedCacheKey = _resolveCacheKey(finalUrl);
    return CachedNetworkImage(
      imageUrl: finalUrl,
      cacheKey: resolvedCacheKey,
      width: width,
      height: height,
      fit: fit,
      filterQuality: FilterQuality.medium,
      useOldImageOnUrlChange: useOldImageOnUrlChange,
      httpHeaders: const { // *可爱*网易云，直接给403
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/42.0.2311.135 Safari/537.36 Edge/13.10586',
        'Referer': 'https://music.163.com/',
      },
      placeholder: (context, url) => placeholder ?? _defaultPlaceholder(context),
      errorWidget: (context, url, error) {
        return errorWidget ?? _defaultErrorWidget(context);
      },
      fadeInDuration: enableFade ? const Duration(milliseconds: 300) : Duration.zero,
      fadeOutDuration: enableFade ? const Duration(milliseconds: 200) : Duration.zero,
      memCacheWidth: pWidth,
      memCacheHeight: pHeight,
    );
  }

  String _normalizeUrl(String rawUrl) {
    if (rawUrl.isEmpty) return rawUrl;
    String finalUrl = rawUrl.replaceFirst('https://', 'http://');
    final Uri? uri = Uri.tryParse(finalUrl);
    final bool isLocalProxyImage =
        uri != null && uri.host == '127.0.0.1' && uri.path == '/image';
    if (isLocalProxyImage) {
      // url= 永远是第一个参数，第一个 & 就是它的边界
      final int amp = finalUrl.indexOf('&');
      return amp >= 0
          ? '${finalUrl.substring(0, amp)}%3Fparam%3D${pWidth}y$pHeight${finalUrl.substring(amp)}'
          : '$finalUrl%3Fparam%3D${pWidth}y$pHeight';
    }
    if (!finalUrl.contains('?')) {
      return '$finalUrl?param=${pWidth}y$pHeight';
    }
    if (!finalUrl.contains('param=')) {
      return '$finalUrl&param=${pWidth}y$pHeight';
    }
    return finalUrl;
  }

  String? _resolveCacheKey(String finalUrl) {
    final String? custom = cacheKey?.trim();
    if (custom != null && custom.isNotEmpty) return custom;

    final Uri? uri = Uri.tryParse(finalUrl);
    if (uri == null) return null;

    final bool isLocalProxyImage =
        uri.host == '127.0.0.1' && uri.path == '/image';
    if (!isLocalProxyImage) return null;

    final String pid = uri.queryParameters['pid']?.trim() ?? '';
    if (pid.isEmpty) return null;
    return 'proxy_image_${pid}_${pWidth}x$pHeight';
  }

  Color _placeholderBg(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? Colors.black : Colors.grey.shade200;
  }

  Widget _defaultPlaceholder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      color: _placeholderBg(context),
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note,
        size: 20.sp,
        color: isDark ? Colors.grey.shade700 : Colors.white24,
      ),
    );
  }

  Widget _defaultErrorWidget(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: _placeholderBg(context),
      alignment: Alignment.center,
      child: Icon(
        Icons.broken_image,
        color: Colors.grey.shade500,
      ),
    );
  }
}
