# DataMatrix Scanner

Ứng dụng web quét mã **DataMatrix** bằng camera, chạy hoàn toàn trên trình duyệt. Không cần cài đặt, không gửi dữ liệu lên máy chủ.

## Tính năng

- Quét mã DataMatrix trực tiếp từ camera (webcam / camera điện thoại)
- Chọn camera khi có nhiều thiết bị
- Quét từ ảnh tải lên (khi không có camera)
- Hiển thị kết quả, sao chép nhanh, lưu lịch sử quét gần đây
- Giao diện tiếng Việt, tối ưu cho mobile

## Sử dụng trực tuyến

Sau khi bật GitHub Pages, truy cập:

**https://bachlong12623.github.io/ReadDatamatrix/**

## Triển khai lên GitHub Pages

1. Vào **Settings → Pages** của repository
2. Chọn **Source: GitHub Actions**
3. Push code lên nhánh `main` — workflow sẽ tự động deploy

Hoặc deploy thủ công: **Actions → Deploy to GitHub Pages → Run workflow**

## Chạy cục bộ

Camera chỉ hoạt động trên **HTTPS** hoặc **localhost**. Dùng một trong các cách sau:

```bash
# Python
python3 -m http.server 8080

# Node.js (npx)
npx serve .
```

Mở http://localhost:8080 trong trình duyệt.

## Công nghệ

- [ZXing Browser](https://github.com/zxing-js/browser) — giải mã DataMatrix
- HTML5, CSS3, JavaScript (ES modules)
- GitHub Pages — hosting tĩnh

## Lưu ý

- Cần cấp quyền truy cập camera khi trình duyệt hỏi
- Đảm bảo ánh sáng đủ và mã DataMatrix nằm trong khung quét
- Hỗ trợ tốt nhất trên Chrome, Edge, Safari (iOS 11+), Firefox

## Giấy phép

MIT
