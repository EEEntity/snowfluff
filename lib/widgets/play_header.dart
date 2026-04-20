// 顶部收起按钮

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class PlayHeader extends StatelessWidget {
  const PlayHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 10.w),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.expand_more_rounded, size: 32.sp, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
