// 控制图标组件

import 'package:snowfluff/common/music_handler.dart';
import 'package:snowfluff/pages/provider.dart';
import 'package:snowfluff/router/app_router.dart';
import 'package:snowfluff/router/router.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

class PlaybackControlBar extends ConsumerWidget {
  const PlaybackControlBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFM = ref.watch(
      isFMModeProvider.select((s) => s.value ?? false),
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 播放队列(FM模式下禁用)
          IconButton(
            onPressed: isFM
                ? null
                : () async {
                    if (context.canPop()) {
                      context.pop();
                    }
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      final shellContext = shellNavigatorKey.currentContext;
                      if (shellContext == null) return;
                      final path = GoRouter.of(shellContext).state.path;
                      if (path != AppRouter.playqueue) {
                        shellContext.push(AppRouter.playqueue);
                      }
                    });
                  },
            icon: Icon(
              Icons.queue_music,
              size: 28.sp,
              color: isFM ? Colors.white24 : Colors.white70,
            ),
          ),
          // 上一曲 / FM模式下"不喜欢"
          IconButton(
            onPressed: isFM
                ? () => SnowfluffMusicHandler().personalFMTrash()
                : () => SnowfluffMusicHandler().skipToPrevious(),
            icon: Icon(
              isFM ? Icons.thumb_down_outlined : Icons.skip_previous_rounded,
              size: isFM ? 20.sp : 28.sp,
              color: Colors.white,
            ),
          ),
          // 播放/暂停
          const PlayPauseButton(),
          // 下一曲
          IconButton(
            onPressed: () => SnowfluffMusicHandler().skipToNext(),
            icon: Icon(Icons.skip_next_rounded, size: 28.sp, color: Colors.white),
          ),
          // 循环模式切换(FM模式下强制列表循环)
          LoopModeButton(disabled: isFM),
        ],
      ),
    );
  }
}

class PlayPauseButton extends ConsumerWidget {
  const PlayPauseButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = ref.watch(
      playbackStateProvider.select((s) => s.value?.playing ?? false),
    );

    return IconButton(
      onPressed: () {
        if (isPlaying) {
          SnowfluffMusicHandler().pause();
        } else {
          SnowfluffMusicHandler().play();
        }
      },
      // 这里的图标大一些，视觉重心在中央
      icon: Icon(
        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        size: 40.sp, 
        color: Colors.white,
      ),
    );
  }
}

class LoopModeButton extends ConsumerWidget {
  final bool disabled;
  const LoopModeButton({super.key, this.disabled = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shuffleEnabled = ref.watch(
      playbackStateProvider.select(
        (s) => s.value?.shuffleMode == AudioServiceShuffleMode.all,
      ),
    );
    final loopMode = ref.watch(loopModeProvider);

    IconData icon;
    if (shuffleEnabled) {
      icon = Icons.shuffle_rounded;
    } else if (loopMode == AudioServiceRepeatMode.one) {
      icon = Icons.repeat_one_rounded;
    } else {
      icon = Icons.repeat_rounded;
    }

    return IconButton(
      onPressed: disabled ? null : () => SnowfluffMusicHandler().changeLoopMode(),
      icon: Icon(
        icon,
        size: 26.sp,
        color: disabled ? Colors.white24 : Colors.white70,
      ),
    );
  }
}
