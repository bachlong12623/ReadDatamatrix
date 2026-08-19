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

### Đồng bộ GitHub JSON (khuyên dùng cho 1 người)

Lưu scans vào [`data/scans.json`](data/scans.json) trên repo — điện thoại và máy tính cùng đọc/ghi.

**Không dùng SQLite trên GitHub** (không có DB server; file binary khó merge).

#### Cách bật

1. Tạo [Fine-grained PAT](https://github.com/settings/personal-access-tokens/new):
   - Repository: `ReadDatamatrix`
   - Permissions → **Contents: Read and write**
2. Mở app → **Token** → dán PAT → Lưu
3. Bấm **Sync GitHub** (hoặc đợi ~2s sau mỗi lần quét — tự đẩy)

Token chỉ lưu trong trình duyệt/máy bạn, không commit lên git.

#### Xuất file thủ công

Vẫn có **Tải CSV/TXT** nếu muốn file offline.

## Cách dùng

1. Cho phép quyền camera khi được hỏi.
2. Đưa mã Data Matrix vào khung quét.
3. Kết quả hiện ở panel bên cạnh (hoặc bên dưới trên mobile).
4. **Sao chép** để lấy nội dung; nhấn giữ mục lịch sử để copy nhanh.
5. Dùng nút flash / đổi camera / **zoom 1×–4×** / **chế độ quét** trên thanh tiêu đề khi cần.
6. **Quét từ ảnh** (web): decode song song zxing + rxing (chỉ khi chọn ảnh, không ảnh hưởng camera).

## Công nghệ

- [Flutter](https://flutter.dev/)
- [mobile_scanner](https://pub.dev/packages/mobile_scanner) — Data Matrix (ML Kit / Vision / zxing-wasm)
- **zxing-wasm** + **rxing-wasm** decode song song trên web (`web/multi_decoder.js`)

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
