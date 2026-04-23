# Snowfluff Music

第三方网易云播放器

参考了[bujuan](https://github.com/2697a/bujuan)(框架与[接口](https://github.com/neteasecloudmusicapienhanced/api-enhanced)实现)和[YesPlayMusic](https://github.com/qier222/YesPlayMusic)(部分页面布局)

![Android平板](./images/screenshot_tablet.jpg)

## 适用平台
 - Android 手机/平板
 - Linux桌面(还没做[MPRIS](https://wiki.archlinux.org/title/MPRIS))

## 功能
 - 手机短信/二维码/cookies登录
 - 发现页：每日推荐/私人FM模式
 - 搜索歌手/专辑/歌单/单曲
 - 音质选择

## 需要完善
 - 应用图标
 - 桌面端MPRIS/快捷键监听
 - library页面图像
 - 刷新cookies避免过期
 - 其它平台

## setup

```bash
# flutter create --platforms=android .
flutter pub get
dart run build_runner build --delete-conflicting-outputs
# Android/arm64平台
flutter build apk --target-platform=android-arm64 --release --extra-gen-snapshot-options=--strip --split-debug-info=debug-info
```
