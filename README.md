# DataMatrix Reader

Ứng dụng Flutter đọc mã **Data Matrix** trên **iOS**, **Android** và **Web**.

## Yêu cầu

- [Flutter](https://docs.flutter.dev/get-started/install) 3.11+
- Camera (thiết bị thật hoặc trình duyệt có webcam)
- Web: chạy trên **localhost** hoặc **HTTPS** (trình duyệt mới cho phép camera)

## Chạy

```bash
flutter pub get
dart run tool/patch_mobile_scanner.dart   # bắt buộc: đảo màu (web) + xen kẽ polarity (Android)
```

### Web

```bash
flutter run -d chrome
```

### Android

```bash
flutter run -d android
```

### iOS (cần macOS + Xcode)

```bash
flutter run -d ios
```

> Sau mỗi `flutter pub get` / nâng cấp package, chạy lại `dart run tool/patch_mobile_scanner.dart`.
> CI GitHub Pages cũng chạy bước này trước khi build.

### iPhone Air (Safari)

Trang web đã tối ưu cho iPhone Air trên Safari:

- Camera sau **1×** (Fusion Main), khóa zoom tránh nhảy lens 2×
- `playsinline` + autofocus liên tục
- Khung quét lớn hơn, chạm preview để lấy nét lại
- Giữ máy khoảng **15–25 cm** trước mã, đủ sáng

Mở: https://bachlong12623.github.io/ReadDatamatrix/
## Cách dùng

1. Cho phép quyền camera khi được hỏi.
2. Đưa mã Data Matrix vào khung quét.
3. Kết quả hiện ở panel bên cạnh (hoặc bên dưới trên mobile).
4. **Sao chép** để lấy nội dung; nhấn giữ mục lịch sử để copy nhanh.
5. Dùng nút flash / đổi camera trên thanh tiêu đề khi cần.

## Công nghệ

- [Flutter](https://flutter.dev/)
- [mobile_scanner](https://pub.dev/packages/mobile_scanner) — Data Matrix trên Android (ML Kit), iOS (Vision), Web (zxing-wasm)

## Build release

```bash
flutter build apk
flutter build ios
flutter build web
```

## GitHub Pages

Mỗi lần push lên `master`, GitHub Actions build web và deploy lên:

**https://bachlong12623.github.io/ReadDatamatrix/**

Camera trên Pages cần HTTPS (GitHub Pages đã có). Cho phép quyền camera khi trình duyệt hỏi.

Build local giống CI:

```bash
flutter build web --release --base-href /ReadDatamatrix/
```
