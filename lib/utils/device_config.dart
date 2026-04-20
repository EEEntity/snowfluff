import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';

enum LayoutMode {
  desktop, // Linux: 非触屏, 横屏, 宽设计尺寸
  tablet, // Android Tablet: 触屏, 横屏, 宽设计尺寸
  mobile, // Android Phone: 触屏, 竖屏, 窄设计尺寸
}

class DeviceConfig {
  static final DeviceConfig _instance = DeviceConfig._internal();
  factory DeviceConfig() => _instance;
  DeviceConfig._internal();
  late final LayoutMode mode;
  late final bool isTouch;
  late final Size designSize;
  static const String _boxName = 'device_config';
  Future<bool> loadConfig() async {
    final box = await Hive.openBox(_boxName);
    if (box.containsKey('mode')) { // 只要包含mode就认为配置存在
      mode = LayoutMode.values[box.get('mode')];
      isTouch = box.get('isTouch');
      designSize = Size(box.get('width'), box.get('height'));
      return true;
    }
    return false;
  }
  Future<void> init(Size physicalSize, double devicePixelRatio) async {
    // 将物理像素转换为逻辑像素进行判断
    final width = physicalSize.width / devicePixelRatio;
    final height = physicalSize.height / devicePixelRatio;
    final shortestSide = width < height ? width : height;
    if (Platform.isLinux) {
      mode = LayoutMode.desktop;
      isTouch = false;
      designSize = const Size(1024, 700);
    } else {
      isTouch = true;
      if (_isTablet(shortestSide)) {
        mode = LayoutMode.tablet;
        designSize = const Size(1024, 700);
      } else {
        mode = LayoutMode.mobile;
        designSize = const Size(375, 812);
      }
    }
    // 存入Hive
    final box = await Hive.openBox(_boxName);
    await box.putAll({
      'mode': mode.index,
      'isTouch': isTouch,
      'width': designSize.width,
      'height': designSize.height,
    });
  }
  Future<void> reset() async {
    final box = await Hive.openBox(_boxName);
    await box.clear();
  }
  bool _isTablet(double shortestSide) {
    return shortestSide >= 600;
  }
  static bool get isDesktop => _instance.mode == LayoutMode.desktop;
  static bool get isTablet => _instance.mode == LayoutMode.tablet;
  static bool get isMobile => _instance.mode == LayoutMode.mobile;
  static bool get isTouchDevice => _instance.isTouch;
  static LayoutMode get layoutMode => _instance.mode;
}
