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
    <a href="#shortcuts">Phím tắt</a> •
    <a href="#development">Development</a> •
    <a href="#documentation">Tài liệu</a> •
    <a href="#community">Cộng đồng</a> •
    <a href="#security">Bảo mật</a> •
    <a href="#contributing">Đóng góp</a>
  </p>

  <p>
    <a href="https://deepwiki.com/duongductrong/Snapzy"><img alt="Hỏi DeepWiki" src="https://deepwiki.com/badge.svg" /></a>
    <a href="https://discord.gg/6CRdUKaC"><img alt="Tham gia cộng đồng Discord" src="https://img.shields.io/badge/Discord-Join%20Community-5865F2?style=flat&amp;logo=discord&amp;logoColor=white" /></a>
    <a href="#featured-on"><img alt="Được giới thiệu trên" src="https://img.shields.io/badge/Featured%20On-Product%20Hunt%20%2B%20Unikorn-111827?style=flat&amp;logo=producthunt&amp;logoColor=white" /></a>
  </p>
</div>

<a id="features"></a>

## Tính năng

- **Chụp màn hình**: chụp toàn màn hình hoặc vùng chọn với chuyển đổi giữa chế độ chọn tay/chế độ cửa sổ ứng dụng (`Application Capture`, mặc định `A`), chụp cuộn với xem trước ghép ảnh trực tiếp, trích xuất văn bản OCR, chụp cắt đối tượng nền trong suốt với tự động crop an toàn tùy chọn, giữ bóng cửa sổ (macOS 14+), xuất nhiều định dạng (PNG/JPG/WebP), ẩn icon/widget desktop, chụp nhanh khi đang quay
- **Quay màn hình**: xuất video hoặc GIF, thu âm thanh hệ thống + microphone, làm nổi bật cú nhấp chuột, overlay phím bấm, chú thích trực tiếp trên màn hình, nhớ vùng quay gần nhất, resize GIF, metadata Smart Camera cho chỉnh sửa Follow Mouse
- **Trình chỉnh sửa chú thích**: shape, mũi tên, văn bản, hình chữ nhật tô màu, blur/pixelate, counter, crop, xóa nền với auto-crop nhận biết vùng cắt, nền mockup với 3D renderer, zoom/pan (pinch + bàn phím), kéo thả sang app khác, shortcut công cụ có thể cấu hình
- **Thiết lập sau khi chụp**: ma trận hành động theo từng chế độ cho lưu, Quick Access, copy clipboard và annotate, cùng một tùy chọn auto-crop toàn cục riêng cho remove background (bật mặc định)
- **Trình chỉnh sửa video**: cắt với timeline trực quan + dải frame, zoom segment với auto-focus (Follow Mouse), nền wallpaper + padding, kích thước export tùy chỉnh, trình xem GIF động, undo/redo
- **Quick Access**: bảng nổi sau mỗi lần chụp với các thao tác copy, edit, drag-to-app, open và delete
- **Shortcut**: shortcut toàn cục cấu hình đầy đủ cho chụp, quay và công cụ annotate, có bật/tắt cho từng shortcut và phát hiện xung đột hệ thống
- **Onboarding**: màn hình chào, chọn ngôn ngữ lần đầu, hướng dẫn cấp quyền, và cấu hình shortcut cho người dùng lần đầu
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

<a id="shortcuts"></a>

## Phím tắt

| Tác vụ                                                            | Phím tắt |
| ----------------------------------------------------------------- | -------- |
| Chụp toàn màn hình                                                | `⇧⌘3`    |
| Chụp vùng                                                         | `⇧⌘4`    |
| ↳ Chuyển chế độ chọn vùng/cửa sổ ứng dụng (`Application Capture`) | `A`      |
| Chụp cuộn                                                         | `⇧⌘6`    |
| Quay màn hình                                                     | `⇧⌘5`    |
| OCR văn bản                                                       | `⇧⌘2`    |
| Chụp tách nền đối tượng                                           | `⇧⌘1`    |
| Mở Annotate                                                       | `⇧⌘A`    |
| Mở Video Editor                                                   | `⇧⌘E`    |
| Mở Cloud Uploads                                                  | `⇧⌘L`    |
| Hiện danh sách shortcut                                           | `⇧⌘K`    |

<a id="development"></a>

## Development

Để setup local, build từ source, và bắt đầu workflow phát triển, hãy đọc [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

Nếu bạn cần lệnh archive, export, hoặc đóng gói DMG, xem [docs/BUILD.md](docs/BUILD.md). Nếu bạn muốn workflow đóng góp, xem [CONTRIBUTING.md](CONTRIBUTING.md).

<a id="documentation"></a>

## Tài liệu

- [Hỏi DeepWiki (trợ lý tài liệu tương tác)](https://deepwiki.com/duongductrong/Snapzy)
- [Bản đồ tài liệu cho con người và agent](docs/README.md)
- [Cấu trúc dự án và kiến trúc runtime](docs/STRUCTURE.md)
- [Luồng chụp, quay và chỉnh sửa](docs/CAPTURE.md)
- [Hướng dẫn build và đóng gói](docs/BUILD.md)
- [Quy trình release và update](docs/RELEASES.md)
- [Kiểm thử update Sparkle cục bộ](docs/UPDATE_TESTING.md)

<a id="community"></a>

## Cộng đồng

- Tham gia cộng đồng Snapzy trên Discord để nhận hỗ trợ, góp ý và thảo luận: [https://discord.gg/6CRdUKaC](https://discord.gg/6CRdUKaC)

<a id="featured-on"></a>

## Được giới thiệu trên

<p>
  <a href="https://www.producthunt.com/products/snapzy?embed=true&amp;utm_source=badge-featured&amp;utm_medium=badge&amp;utm_campaign=badge-snapzy" target="_blank" rel="noopener noreferrer"><img alt="Snapzy - Hãy nghĩ tới CleanShot X nhưng mã nguồn mở và thân thiện với developer | Product Hunt" width="250" height="54" src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1097629&amp;theme=light&amp;t=1773585048784"></a>
  <a href="https://unikorn.vn/p/snapzy?ref=embed-snapzy" target="_blank"><img src="https://unikorn.vn/api/widgets/badge/snapzy?theme=light" alt="Snapzy trên Unikorn.vn" style="width: 250px; height: 54px;" width="250" height="54" /></a>
</p>

## Benchmark

### OCR

Ngày benchmark: 19 tháng 4, 2026. Các con số OCR trong README được lấy từ runner có thể tái lập `scripts/ocr_readme_benchmark.swift`, chạy trên corpus sạch dạng UI/article text có xuống dòng với `12 mẫu / ngôn ngữ` trên `10 ngôn ngữ được hỗ trợ`. `Character accuracy` là chỉ số chính, `exact match` được tính rất chặt, và tỷ lệ `no-output` trên corpus này là `0%` cho toàn bộ bảng bên dưới.

| Ngôn ngữ | Character Accuracy | Exact Match |
| --- | ---: | ---: |
| English | 100.0% | 100.0% |
| Vietnamese | 100.0% | 100.0% |
| Simplified Chinese | 99.3% | 75.0% |
| Traditional Chinese | 99.0% | 66.7% |
| Spanish | 99.9% | 91.7% |
| Japanese | 99.4% | 66.7% |
| Korean | 99.7% | 83.3% |
| Russian | 100.0% | 100.0% |
| French | 99.3% | 33.3% |
| German | 99.8% | 75.0% |

Screenshot thực tế có thể thấp hơn corpus này, nhất là khi có emoji, footer tương phản thấp, dấu câu lạ, nền gradient, blur, hoặc font trang trí mạnh.

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
