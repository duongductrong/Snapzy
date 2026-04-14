<div align="center">
  <img src="./banner.png" width="200" height="200" alt="Banner Snapzy" />

  <h1>Snapzy</h1>
  <p><strong>Chụp màn hình, quay màn hình, chú thích và chỉnh sửa macOS thuần native ngay từ thanh menu.</strong></p>

  <p>
    Built with <a href="https://developer.apple.com/xcode/swiftui/">SwiftUI</a>,
    <a href="https://developer.apple.com/documentation/appkit">AppKit</a>,
    <a href="https://developer.apple.com/documentation/screencapturekit">ScreenCaptureKit</a>,
    <a href="https://developer.apple.com/documentation/vision">Vision</a>, and
    <a href="https://sparkle-project.org/">Sparkle</a>.
  </p>

  <p>
    <a href="./README.md">🇺🇸 English</a> •
    <a href="./README.vi.md">🇻🇳 Tiếng Việt</a> •
    <a href="./README.zh-CN.md">🇨🇳 简体中文</a>
  </p>

  <p>
    <a href="#features">Tính năng</a> •
    <a href="#install">Cài đặt</a> •
    <a href="#build-from-source">Build từ source</a> •
    <a href="#documentation">Tài liệu</a> •
    <a href="#security">Bảo mật</a> •
    <a href="#contributing">Đóng góp</a>
  </p>

  <p>
    <a href="https://deepwiki.com/duongductrong/Snapzy"><img alt="Hỏi DeepWiki" src="https://deepwiki.com/badge.svg" /></a>
    <a href="#featured-on"><img alt="Được giới thiệu trên" src="https://img.shields.io/badge/Featured%20On-Product%20Hunt%20%2B%20Unikorn-111827?style=flat&amp;logo=producthunt&amp;logoColor=white" /></a>
  </p>
</div>

<a id="features"></a>
## Tính năng

- **Chụp màn hình**: chụp toàn màn hình hoặc vùng chọn, chụp cuộn với xem trước ghép ảnh trực tiếp, trích xuất văn bản OCR, chụp cắt đối tượng nền trong suốt với tự động crop an toàn tùy chọn, giữ bóng cửa sổ (macOS 14+), xuất nhiều định dạng (PNG/JPG/WebP), ẩn icon/widget desktop, chụp nhanh khi đang quay
- **Quay màn hình**: xuất video hoặc GIF, thu âm thanh hệ thống + microphone, làm nổi bật cú nhấp chuột, overlay phím bấm, chú thích trực tiếp trên màn hình, nhớ vùng quay gần nhất, resize GIF, metadata Smart Camera cho chỉnh sửa Follow Mouse
- **Trình chỉnh sửa chú thích**: shape, mũi tên, văn bản, hình chữ nhật tô màu, blur/pixelate, counter, crop, xóa nền với auto-crop nhận biết vùng cắt, nền mockup với 3D renderer, zoom/pan (pinch + bàn phím), kéo thả sang app khác, shortcut công cụ có thể cấu hình
- **Thiết lập sau khi chụp**: ma trận hành động theo từng chế độ cho lưu, Quick Access, copy clipboard và annotate, cùng một tùy chọn auto-crop toàn cục riêng cho remove background (bật mặc định)
- **Trình chỉnh sửa video**: cắt với timeline trực quan + dải frame, zoom segment với auto-focus (Follow Mouse), nền wallpaper + padding, kích thước export tùy chỉnh, trình xem GIF động, undo/redo
- **Quick Access**: bảng nổi sau mỗi lần chụp với các thao tác copy, edit, drag-to-app, open và delete
- **Shortcut**: shortcut toàn cục cấu hình đầy đủ cho chụp, quay và công cụ annotate, có bật/tắt cho từng shortcut và phát hiện xung đột hệ thống
- **Onboarding**: màn hình chào, hướng dẫn cấp quyền, và cấu hình shortcut cho người dùng lần đầu
- **Bản địa hóa**: bản địa hóa ứng dụng cho 🇺🇸 English, 🇻🇳 Vietnamese, 🇨🇳 Simplified Chinese, 🇹🇼 Traditional Chinese, 🇪🇸 Spanish, 🇯🇵 Japanese, 🇰🇷 Korean, 🇷🇺 Russian, 🇫🇷 French và 🇩🇪 German, hỗ trợ chọn ngôn ngữ riêng cho từng app theo macOS
- **Cloud Upload**: quyền riêng tư trước hết với mô hình tự mang storage bằng AWS S3 hoặc Cloudflare R2, không dùng server bên thứ ba, upload thủ công từ Quick Access hoặc Annotate, credential lưu trong macOS Keychain với bảo vệ mật khẩu tùy chọn, import/export credential mã hóa thủ công để thiết lập nhanh trên Mac khác, lịch sử upload, auto-expiration cấu hình được (1–90 ngày hoặc vĩnh viễn), lifecycle rules, hỗ trợ custom domain
- **Cập nhật & chẩn đoán**: cập nhật trong app qua Sparkle, crash reporting, quản lý cache
- **Nền tảng**: app thanh menu, giao diện light/dark/system, App Sandbox với bookmark truy cập file an toàn

<a id="install"></a>
## Cài đặt

> Yêu cầu **macOS 13.0** trở lên.

### Homebrew

```bash
brew tap duongductrong/snapzy https://github.com/duongductrong/Snapzy
brew install --cask snapzy
```

### Script shell

```bash
# Cài một phiên bản cụ thể
curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/v1.7.0/install.sh | bash
```

### Tải bản phát hành

1. Mở [Releases](https://github.com/duongductrong/Snapzy/releases)
2. Tải asset ứng dụng đã đóng gói mới nhất, thường là `Snapzy-v<version>.dmg`
3. Di chuyển `Snapzy.app` vào `/Applications`
4. Mở Snapzy
5. Cấp quyền Screen Recording khi macOS nhắc trong System Settings
6. Mở lại Snapzy sau khi cấp quyền Screen Recording nếu macOS yêu cầu
7. Cấp thêm quyền Microphone nếu bạn muốn ghi giọng nói trong video

## Gỡ cài đặt

Để xóa hoàn toàn Snapzy, reset mọi quyền và dọn dữ liệu ứng dụng:

```bash
curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/master/uninstall.sh | bash
```

Hoặc nếu bạn đã clone repo:

```bash
./uninstall.sh
```

Lệnh này sẽ xóa ứng dụng khỏi `/Applications`, xóa preferences và cache, đồng thời reset quyền TCC (Screen Recording, Microphone, Accessibility). Bạn có thể cần đăng xuất hoặc khởi động lại để thay đổi quyền có hiệu lực hoàn toàn.

<a id="build-from-source"></a>
## Build từ source

> Yêu cầu **Xcode 15.0+** và Command Line Tools (`xcode-select --install`).

1. Clone repository:

```bash
git clone https://github.com/duongductrong/Snapzy.git
cd Snapzy
```

2. Mở project:

```bash
open Snapzy.xcodeproj
```

3. Build và chạy với `Cmd+R`

Bạn cũng có thể build từ terminal:

```bash
xcodebuild -project Snapzy.xcodeproj -scheme Snapzy -configuration Debug build
```

Chi tiết đóng gói bản phát hành nằm ở [docs/project-build.md](docs/project-build.md).

<a id="documentation"></a>
## Tài liệu

- [Hỏi DeepWiki (trợ lý tài liệu tương tác)](https://deepwiki.com/duongductrong/Snapzy)
- [Bản đồ tài liệu cho con người và agent](docs/README.md)
- [Cấu trúc dự án và kiến trúc runtime](docs/project-structure.md)
- [Luồng chụp, quay và chỉnh sửa](docs/capture-flow.md)
- [Hướng dẫn build dự án](docs/project-build.md)
- [Quy trình release và update](docs/project-workflow.md)
- [Kiểm thử update Sparkle cục bộ](docs/local-update-testing.md)

<a id="featured-on"></a>
## Được giới thiệu trên

<p>
  <a href="https://www.producthunt.com/products/snapzy?embed=true&amp;utm_source=badge-featured&amp;utm_medium=badge&amp;utm_campaign=badge-snapzy" target="_blank" rel="noopener noreferrer"><img alt="Snapzy - Hãy nghĩ tới CleanShot X nhưng mã nguồn mở và thân thiện với developer | Product Hunt" width="250" height="54" src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1097629&amp;theme=light&amp;t=1773585048784"></a>
  <a href="https://unikorn.vn/p/snapzy?ref=embed-snapzy" target="_blank"><img src="https://unikorn.vn/api/widgets/badge/snapzy?theme=light" alt="Snapzy trên Unikorn.vn" style="width: 250px; height: 54px;" width="250" height="54" /></a>
</p>

<a id="security"></a>
## Bảo mật

Snapzy chạy trong macOS App Sandbox với tập entitlement tối thiểu. Mọi request mạng chỉ phục vụ kiểm tra cập nhật Sparkle và các lần cloud upload do chính người dùng chủ động tới bucket S3/R2 của riêng mình, không có dữ liệu nào được gửi tới server bên thứ ba. Credential cloud được lưu độc quyền trong macOS Keychain, có thể được bảo vệ thêm bằng mật khẩu tùy chọn (băm SHA-256, không bao giờ lưu plaintext), và chỉ có thể chuyển qua luồng export/import mã hóa thủ công được bảo vệ bằng passphrase do người dùng cung cấp. Snapzy không thu thập telemetry.

Để báo cáo lỗ hổng bảo mật, hãy dùng [GitHub Security Advisory](https://github.com/duongductrong/Snapzy/security/advisories/new) hoặc liên hệ riêng với maintainer. Xem [SECURITY.md](SECURITY.md) để biết đầy đủ chi tiết.

<a id="contributing"></a>
## Đóng góp

Mọi đóng góp đều được chào đón. Hãy đọc [CONTRIBUTING.md](CONTRIBUTING.md) trước khi mở pull request.

## Lịch sử sao

<a href="https://www.star-history.com/?repos=duongductrong%2FSnapzy&type=date&logscale=&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/image?repos=duongductrong/Snapzy&type=date&theme=dark&logscale&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/image?repos=duongductrong/Snapzy&type=date&logscale&legend=top-left" />
   <img alt="Biểu đồ lịch sử sao" src="https://api.star-history.com/image?repos=duongductrong/Snapzy&type=date&logscale&legend=top-left" />
 </picture>
</a>

## Giấy phép

BSD 3-Clause License. Xem [LICENSE](LICENSE).
