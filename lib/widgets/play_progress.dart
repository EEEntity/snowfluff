// 播放进度条

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// 负责布局时间和进度条，与外部数据对接
class MusicProgressBar extends StatelessWidget {
  final int positionMs; // 当前播放毫秒
  final int durationMs; // 总时长毫秒
  final ValueChanged<double> onChangeEnd; // 拖拽/点击后的回调

  const MusicProgressBar({
    super.key,
    required this.positionMs,
    required this.durationMs,
    required this.onChangeEnd,
  });

  /// 格式化时间函数：支持超过60分钟的情况(130:05)
  String _formatDurationMs(int ms) {
    final totalSeconds = (ms <= 0) ? 0 : ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return "$minutes:${seconds.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final safeDurationMs = durationMs <= 0 ? 0 : durationMs;
    final clampedPositionMs = positionMs.clamp(0, safeDurationMs == 0 ? 0 : safeDurationMs);
    final progress = safeDurationMs == 0 ? 0.0 : clampedPositionMs / safeDurationMs;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 隔离重绘区域
        RepaintBoundary(
          child: SimpleMusicSlider(
            progress: progress,
            playedColor: Colors.white,
            unplayedColor: Colors.white.withValues(alpha: 0.12),
            thumbColor: Colors.white,
            barHeight: 4.w,
            thumbRadius: 6.w,
            onChangeEnd: onChangeEnd,
          ),
        ),
        SizedBox(height: 8.h),
        // 时间显示行
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 2.w),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDurationMs(clampedPositionMs),
                style: TextStyle(color: Colors.white60, fontSize: 12.sp),
              ),
              Text(
                _formatDurationMs(safeDurationMs),
                style: TextStyle(color: Colors.white60, fontSize: 12.sp),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 处理手势逻辑和绘制
class SimpleMusicSlider extends StatefulWidget {
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final Color? thumbColor;
  final double barHeight;
  final double thumbRadius;
  final ValueChanged<double> onChangeEnd;

  const SimpleMusicSlider({
    super.key,
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
    required this.onChangeEnd,
    this.thumbColor,
    this.barHeight = 4.0,
    this.thumbRadius = 8.0,
  });

  @override
  State<SimpleMusicSlider> createState() => _SimpleMusicSliderState();
}

class _SimpleMusicSliderState extends State<SimpleMusicSlider> {
  bool _isDragging = false; // 是否正在拖拽，用于拦截外部进度更新
  double _localProgress = 0; // 本地保存的进度，用于手势交互时的平滑显示

  @override
  void initState() {
    super.initState();
    _localProgress = widget.progress;
  }

  @override
  void didUpdateWidget(covariant SimpleMusicSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果正在拖拽，忽略外部(播放器)传入的进度更新
    if (_isDragging) return;
    final next = widget.progress.clamp(0.0, 1.0);
    if ((next - _localProgress).abs() < 0.0001) return; // 进度变化太小，忽略
    _localProgress = next;
  }

  void _updatePosition(Offset localPos, double width) {
    if (width <= 0) return;
    final next = (localPos.dx / width).clamp(0.0, 1.0);
    if ((next - _localProgress).abs() < 0.0001) return; // 进度变化太小，忽略
    setState(() {
      _localProgress = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // 点击热区
        final double hitHeight = widget.thumbRadius * 4;

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_) => setState(() => _isDragging = true),
          onHorizontalDragUpdate: (d) => _updatePosition(d.localPosition, width),
          onHorizontalDragEnd: (_) {
            setState(() => _isDragging = false);
            widget.onChangeEnd(_localProgress);
          },
          onTapDown: (d) {
            _updatePosition(d.localPosition, width);
            widget.onChangeEnd(_localProgress);
          },
          child: SizedBox(
            width: width,
            height: hitHeight,
            child: CustomPaint(
              painter: _SliderPainter(
                progress: _localProgress,
                playedColor: widget.playedColor,
                unplayedColor: widget.unplayedColor,
                thumbColor: widget.thumbColor ?? widget.playedColor,
                barHeight: widget.barHeight,
                // 拖拽时圆球稍微放大
                thumbRadius: _isDragging ? widget.thumbRadius * 1.2 : widget.thumbRadius,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 负责绘制线条和圆圈
class _SliderPainter extends CustomPainter {
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final Color thumbColor;
  final double barHeight;
  final double thumbRadius;
  // 减轻GC压力
  final Paint _paint = Paint()..style = PaintingStyle.fill;

  _SliderPainter({
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
    required this.thumbColor,
    required this.barHeight,
    required this.thumbRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final progressX = size.width * progress;
    final Radius radius = Radius.circular(barHeight / 2);

    // 绘制背景条(未播放部分)
    _paint.color = unplayedColor;
    canvas.drawRRect(
      RRect.fromLTRBR(0, centerY - barHeight / 2, size.width, centerY + barHeight / 2, radius),
      _paint,
    );

    // 已播放条
    _paint.color = playedColor;
    if (progressX > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(0, centerY - barHeight / 2, progressX, centerY + barHeight / 2, radius),
        _paint,
      );
    }

    // 绘制圆球
    _paint.color = thumbColor;
    canvas.drawCircle(Offset(progressX, centerY), thumbRadius, _paint);
  }

  // 只有状态变化时重绘
  @override
  bool shouldRepaint(covariant _SliderPainter oldDelegate) {
    return oldDelegate.progress != progress ||
           oldDelegate.thumbRadius != thumbRadius ||
           oldDelegate.playedColor != playedColor;
  }
}
