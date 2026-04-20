import 'package:snowfluff/pages/provider.dart';
import 'package:snowfluff/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

class DesktopMenu extends ConsumerWidget {
  final double height;
  const DesktopMenu({super.key, this.height = 36});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconSize = 17.sp;
    final buttonSize = height;
    final gap = 22.w;
    final activeColor = Theme.of(context).colorScheme.primary;
    final currentPath = ref.watch(currentRouterPathProvider);

    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () => context.replace(AppRouter.discover),
            constraints: BoxConstraints.tightFor(width: buttonSize, height: buttonSize),
            padding: EdgeInsets.zero,
            icon: Icon(Icons.near_me, size: iconSize,
                color: currentPath == AppRouter.discover ? activeColor : null),
          ),
          SizedBox(width: gap),
          IconButton(
            onPressed: () => context.replace(AppRouter.home),
            constraints: BoxConstraints.tightFor(width: buttonSize, height: buttonSize),
            padding: EdgeInsets.zero,
            icon: Icon(Icons.home, size: iconSize,
                color: currentPath == AppRouter.home ? activeColor : null),
          ),
          SizedBox(width: gap),
          IconButton(
            onPressed: () => context.replace(AppRouter.settings),
            constraints: BoxConstraints.tightFor(width: buttonSize, height: buttonSize),
            padding: EdgeInsets.zero,
            icon: Icon(Icons.settings, size: iconSize,
                color: currentPath == AppRouter.settings ? activeColor : null),
          ),
        ],
      ),
    );
  }
}

class TabletMenu extends ConsumerWidget {
  final double height;
  const TabletMenu({
    super.key,
    this.height = 36,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconSize = 17.sp;
    final buttonSize = height;
    final gap = 22.w;
    final activeColor = Theme.of(context).colorScheme.primary;
    final currentPath = ref.watch(currentRouterPathProvider);
    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () => context.replace(AppRouter.discover),
            constraints: BoxConstraints.tightFor(width: buttonSize, height: buttonSize),
            padding: EdgeInsets.zero,
            icon: Icon(Icons.near_me, size: iconSize,
                color: currentPath == AppRouter.discover ? activeColor : null),
          ),
          SizedBox(width: gap),
          IconButton(
            onPressed: () => context.replace(AppRouter.home),
            constraints: BoxConstraints.tightFor(width: buttonSize, height: buttonSize),
            padding: EdgeInsets.zero,
            icon: Icon(Icons.home, size: iconSize,
                color: currentPath == AppRouter.home ? activeColor : null),
          ),
          SizedBox(width: gap),
          IconButton(
            onPressed: () => context.replace(AppRouter.settings),
            constraints: BoxConstraints.tightFor(width: buttonSize, height: buttonSize),
            padding: EdgeInsets.zero,
            icon: Icon(Icons.settings, size: iconSize,
                color: currentPath == AppRouter.settings ? activeColor : null),
          ),
        ],
      ),
    );
  }
}
