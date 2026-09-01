# Zoomin

一個用 Flutter 實作的 Android 放大鏡實驗 App。目前用來偶爾閱讀小字、查看電子元件腳位，或在焊接時輔助觀察。

目前原型包含：

- 後鏡頭即時預覽
- 獨立的放大與縮小按鈕
- 截圖並儲存到 `Zoomin` 相簿
- 手電筒補光
- 左手／右手模式，工具列會隨直向與橫向調整

## 開發

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

Android release APK（需要本機的 `android/key.properties` 與 release keystore）：

```powershell
flutter clean
flutter pub get
flutter build apk --release
```

建置完成後的 APK 位於 `build/app/outputs/flutter-apk/app-release.apk`。簽署金鑰與密碼只保留在本機，已由 `.gitignore` 排除；請自行備份 `android/app/zoomin-release.jks` 與 `android/key.properties`，遺失後將無法用同一金鑰更新已發佈的 App。

相機、手電筒與相簿儲存需要在 Android 實體裝置上驗證。開發意向與 AI 協作約定請見 `doc/`。
