<div align="center">
  <img src="./banner.png" width="200" height="200" alt="Banner Snapzy" />

  <h1>Snapzy</h1>
  <p><strong>Chụp màn hình, quay màn hình, chú thích và chỉnh sửa native trên macOS, ngay từ thanh menu.</strong></p>

  <p>
    <a href="https://trendshift.io/repositories/24550" target="_blank"><img src="https://trendshift.io/api/badge/repositories/24550" alt="duongductrong%2FSnapzy | Trendshift" style="width: 250px; height: 55px;" width="250" height="55"/></a>
  </p>

  <p>
    Xây dựng bằng <a href="https://developer.apple.com/xcode/swiftui/">SwiftUI</a>,
    <a href="https://developer.apple.com/documentation/appkit">AppKit</a>,
    <a href="https://developer.apple.com/documentation/screencapturekit">ScreenCaptureKit</a>,
    <a href="https://developer.apple.com/documentation/vision">Vision</a> và
    <a href="https://sparkle-project.org/">Sparkle</a>.
  </p>

  <p>
    <a href="./README.md">🇺🇸 English</a> •
    <a href="./README.vi.md">🇻🇳 Tiếng Việt</a> •
    <a href="./README.zh-CN.md">🇨🇳 简体中文</a> •
    <a href="./README.ja.md">🇯🇵 日本語</a>
  </p>

  <p>
    <a href="#install">Cài đặt</a> •
    <a href="#uninstall">Gỡ cài đặt</a> •
    <a href="#quick-start">Bắt đầu nhanh</a> •
    <a href="#what-snapzy-can-do">Snapzy làm được gì</a> •
    <a href="#shortcuts">Phím tắt</a> •
    <a href="#quick-access-card-actions">Thao tác trên thẻ Truy cập nhanh</a> •
    <a href="#command-line-tools">Công cụ dòng lệnh</a> •
    <a href="#automation">Tự động hóa</a> •
    <a href="#security-and-privacy">Bảo mật và quyền riêng tư</a> •
    <a href="#more-details">Tài liệu chi tiết</a> •
    <a href="#contributing">Đóng góp</a> •
    <a href="#contributors">Người đóng góp</a> •
    <a href="#featured-on">Được giới thiệu trên</a> •
    <a href="#star-history">Lịch sử Star</a> •
    <a href="#acknowledgments">Lời cảm ơn</a> •
    <a href="#license">Giấy phép</a>
  </p>

  <p>
    <a href="https://github.com/duongductrong/Snapzy/stargazers"><img alt="GitHub Stars" src="https://img.shields.io/github/stars/duongductrong/Snapzy?style=flat&amp;logo=github" /></a>
    <a href="https://github.com/duongductrong/Snapzy/network/members"><img alt="GitHub Forks" src="https://img.shields.io/github/forks/duongductrong/Snapzy?style=flat&amp;logo=github" /></a>
    <a href="https://github.com/duongductrong/Snapzy/releases"><img alt="GitHub Downloads" src="https://img.shields.io/github/downloads/duongductrong/Snapzy/total?style=flat&amp;logo=github" /></a>
  </p>
  <p>
    <a href="https://deepwiki.com/duongductrong/Snapzy"><img alt="Hỏi DeepWiki" src="https://deepwiki.com/badge.svg" /></a>
    <a href="https://discord.gg/xkWDAuJkZu"><img alt="Tham gia cộng đồng Discord" src="https://img.shields.io/badge/Discord-Join%20Community-5865F2?style=flat&amp;logo=discord&amp;logoColor=white" /></a>
    <a href="https://www.raycast.com/chkzz/snapzy"><img alt="Extension Raycast" src="https://img.shields.io/badge/Raycast-Extension-FF6363?style=flat&amp;logo=raycast&amp;logoColor=white" /></a>
    <a href="#featured-on"><img alt="Được giới thiệu trên" src="https://img.shields.io/badge/Featured%20On-Product%20Hunt%20%2B%20Unikorn-111827?style=flat&amp;logo=producthunt&amp;logoColor=white" /></a>
  </p>
  <p>
    <a href="https://github.com/sponsors/duongductrong"><img alt="GitHub Sponsors" src="https://img.shields.io/badge/Sponsor-%E2%9D%A4-ff69b4?style=flat&amp;logo=github" /></a>
    <a href="https://ko-fi.com/duongductrong"><img alt="Ủng hộ qua Ko-fi" src="https://img.shields.io/badge/Ko--fi-Donate-FF5E5B?style=flat&amp;logo=ko-fi&amp;logoColor=white" /></a>
  </p>
</div>

Snapzy là ứng dụng thanh menu native trên macOS để chụp màn hình, quay màn hình, chú thích và chỉnh sửa. Yêu cầu macOS 13.0 trở lên.

<a id="install"></a>

## Cài đặt

~~~bash
brew install --cask snapzy
~~~

Hoặc cài một phiên bản cụ thể:

~~~bash
curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/v2.1.0/install.sh | bash
~~~

Bạn cũng có thể [tải bản phát hành](https://github.com/duongductrong/Snapzy/releases). Chuyển Snapzy.app vào thư mục /Applications, mở ứng dụng và cấp quyền Ghi màn hình (Screen Recording) khi được hỏi. Mở lại ứng dụng nếu macOS yêu cầu. Quyền Micro và Camera chỉ cần khi bạn ghi kèm các nguồn đó. Snapzy đã được ký số và notarize bởi Apple.

<a id="uninstall"></a>

## Gỡ cài đặt

~~~bash
curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/master/uninstall.sh | bash
~~~

Trong lúc gỡ cài đặt, script sẽ hỏi có xóa thư mục Application Support hay không. Thư mục này có thể chứa ảnh chụp và bản ghi tạm. Trả lời n để giữ lại thư mục đó. Để đặt lại quyền mà không cần gỡ cài đặt, chạy:

~~~bash
curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/master/reset-permissions.sh | bash
~~~

<a id="quick-start"></a>

## Bắt đầu nhanh

1. Nhấn ⇧⌘4 để chụp một vùng, hoặc ⇧⌘3 để chụp toàn màn hình.
2. Dùng thẻ Truy cập nhanh (Quick Access) để sao chép, chú thích, chỉnh sửa, kéo thả hoặc tải lên ảnh vừa chụp.
3. Mở Lịch sử (History) để tìm và dùng lại ảnh chụp màn hình, video và GIF gần đây.

<a id="what-snapzy-can-do"></a>

## Snapzy làm được gì

- **Chụp màn hình**
  - Chụp toàn màn hình, một vùng chọn, cửa sổ ứng dụng hoặc một thành phần giao diện (Smart Element). Chụp được cả popover trên thanh menu của ứng dụng bên thứ ba đang mở; ghép nội dung cuộn thành một ảnh duy nhất với bản xem trước trực tiếp.
  - Trích xuất văn bản bằng OCR Apple Vision tích hợp sẵn hoặc một endpoint tương thích OpenAI do bạn cấu hình. Lấy màu một điểm ảnh bằng kính lúp trực tiếp và sao chép dưới dạng HEX, RGB, HSL, HSB, CMYK, OKLCH hoặc SwiftUI; tách chủ thể khỏi nền, có tùy chọn tự động cắt viền an toàn.
- **Quay màn hình**
  - Quay toàn màn hình hoặc một ứng dụng thành video, có thể kèm âm thanh hệ thống và micro, hoặc lưu bản ghi dưới dạng GIF.
  - Thêm khung camera (hỗ trợ cả Camera liên tục (Continuity Camera) trên iPhone), làm nổi bật cú nhấp chuột và phím bấm, hoặc vẽ chú thích trực tiếp lên màn hình.
- **Chú thích và chỉnh sửa**
  - Thêm mũi tên, hình khối, văn bản, watermark, làm mờ (blur) và pixel hóa. Phát hiện và che dữ liệu nhạy cảm ngay trên máy.
  - Cắt (crop) ảnh, xóa nền và tạo mockup 3D. Cắt ngắn video, thêm đoạn zoom hoặc đoạn đổi tốc độ, và dùng Theo chuột (Follow Mouse) để con trỏ luôn nằm trong khung hình.
- **Truy cập nhanh và Lịch sử**
  - Sao chép, chỉnh sửa, kéo thả hoặc tải lên ảnh chụp ngay từ thẻ Truy cập nhanh nổi; ghim ảnh chụp màn hình lên màn hình.
  - Tìm ảnh chụp màn hình, video và GIF theo tên file, loại hoặc thời gian, rồi mở lại trong trình chỉnh sửa.
- **Tải lên cloud**
  - Tải lên thủ công từ Truy cập nhanh, Chú thích (Annotate), Trình sửa video (Video Editor) hoặc Lịch sử tới AWS S3, Cloudflare R2 hoặc Google Drive.
  - File được tải thẳng lên nhà cung cấp bạn chọn. Snapzy không tự động tải lên sau khi chụp và không chuyển file qua máy chủ của Snapzy.
- **Ngôn ngữ ứng dụng**: hỗ trợ chọn ngôn ngữ riêng cho từng ứng dụng theo cơ chế native của macOS, với 10 ngôn ngữ: tiếng Anh, tiếng Việt, tiếng Trung giản thể, tiếng Trung phồn thể, tiếng Tây Ban Nha, tiếng Nhật, tiếng Hàn, tiếng Nga, tiếng Pháp và tiếng Đức.

<a id="shortcuts"></a>

## Phím tắt

| Thao tác                                                         | Phím tắt     |
| ---------------------------------------------------------------- | ------------ |
| Chụp toàn màn hình                                               | `⇧⌘3`        |
| Chụp vùng chọn                                                   | `⇧⌘4`        |
| ↳ Chuyển giữa chọn thủ công/cửa sổ ứng dụng (`Application Capture`) | `A`       |
| Chụp lại vùng đã chọn                                            | `⌃⌘⇧4`       |
| Chụp vùng và chú thích                                           | `⇧⌘7`        |
| Chụp cửa sổ đang hoạt động                                       | `⇧⌘9`        |
| Chụp cuộn                                                        | `⇧⌘6`        |
| Quay màn hình (bấm để bắt đầu/dừng)                              | `⇧⌘5`        |
| Tạm dừng/Tiếp tục ghi hình (tùy chọn, gợi ý `⌘⇧Space`)           | _chưa gán_   |
| Chụp văn bản (OCR)                                               | `⇧⌘2`        |
| Tách chủ thể                                                     | `⇧⌘1`        |
| Chụp thành phần thông minh (Smart Element)                       | `⌥⇧4`        |
| Mở Chú thích                                                     | `⇧⌘A`        |
| Mở trình sửa video                                               | `⇧⌘E`        |
| Mở cửa sổ Tải lên cloud                                          | `⇧⌘L`        |
| Hiện danh sách phím tắt                                          | `⇧⌘K`        |
| Bật/tắt bảng Lịch sử                                             | `⇧⌘H`        |

<a id="quick-access-card-actions"></a>

## Thao tác trên thẻ Truy cập nhanh

Rê chuột lên một thẻ Truy cập nhanh rồi nhấn phím. Các phím này chỉ hoạt động khi con trỏ đang nằm trên thẻ.

| Thao tác | Phím tắt |
| -------- | -------- |
| Sao chép | `⌘C` |
| Lưu / Mở | `⌘S` |
| Chỉnh sửa | `⌘E` |
| Tải lên cloud | `⌘U` |
| Ghim ảnh chụp lên màn hình | `⌘P` |
| Xóa | `⌘⌫` |
| Đóng | `⌘W` |

<a id="command-line-tools"></a>

## Công cụ dòng lệnh

Công cụ `snapzy` nằm tại `/Applications/Snapzy.app/Contents/Helpers/snapzy`. Để thêm vào `PATH`, mở **Cài đặt → Dòng lệnh** rồi bấm **Cài đặt**.

Quyền truy cập được cấp riêng cho từng ứng dụng gọi lệnh. Mọi lệnh, trừ `snapzy status`, đều yêu cầu ứng dụng gọi lệnh đã được chấp thuận; sau khi chấp thuận, ứng dụng đó có thể chạy các lệnh tiếp theo mà không bị hỏi lại.

~~~bash
snapzy list windows --app Safari
snapzy capture window --app Safari --max-dimension 1568 -o shot.png
snapzy capture area --rect 0,0,800,600 -o area.png
~~~

Xem [tài liệu CLI](docs/CLI.md).

<a id="automation"></a>

## Tự động hóa

Snapzy đăng ký URL scheme `snapzy://` để launcher và công cụ tự động hóa (như [Raycast Extension](https://www.raycast.com/chkzz/snapzy), Alfred hoặc script tự viết) có thể kích hoạt các thao tác chụp. Bạn có thể bật hoặc tắt tích hợp này tại **Cài đặt → Nâng cao → Tích hợp URL Scheme**.

| Thao tác                    | URL                                |
| --------------------------- | ---------------------------------- |
| Chụp toàn màn hình          | `snapzy://capture/fullscreen`      |
| Chụp vùng chọn              | `snapzy://capture/area`            |
| Chụp lại vùng đã chọn       | `snapzy://capture/repeat-area`     |
| Chụp vùng hẹn giờ           | `snapzy://capture/delayed`         |
| Chụp cửa sổ ứng dụng        | `snapzy://capture/application`     |
| Chụp cửa sổ đang hoạt động  | `snapzy://capture/active-window`   |
| Chụp vùng và chú thích      | `snapzy://capture/area-annotate`   |
| Chụp cuộn                   | `snapzy://capture/scrolling`       |
| Chụp văn bản (OCR)          | `snapzy://capture/ocr`             |
| Chụp thành phần thông minh  | `snapzy://capture/smart-element`   |
| Tách chủ thể                | `snapzy://capture/object-cutout`   |
| Quay màn hình               | `snapzy://record/screen`           |
| Quay ứng dụng               | `snapzy://record/application`      |
| Mở Chú thích                | `snapzy://open/annotate`           |
| Ghép ảnh                    | `snapzy://open/combine`            |
| Mở trình sửa video          | `snapzy://open/video-editor`       |
| Mở cửa sổ Tải lên cloud     | `snapzy://open/cloud-uploads`      |
| Mở Lịch sử chụp             | `snapzy://open/history`            |
| Chọn màu                    | `snapzy://tools/pick-color`        |
| Hiện danh sách phím tắt     | `snapzy://show/shortcuts`          |
| Mở Cài đặt                  | `snapzy://settings`                |
| Mở một tab trong Cài đặt    | `snapzy://settings?tab=annotate`   |

`snapzy://open/combine` mở trình chọn ảnh. Công cụ tự động hóa có thể bỏ qua bước chọn bằng cách truyền từ hai đường dẫn file cục bộ trở lên (đã URL-encode) qua tham số `file` lặp lại:

~~~bash
open 'snapzy://open/combine?file=/tmp/first.png&file=/tmp/second.png'
~~~

Xem [Phím tắt và URL scheme](docs/SHORTCUTS.md) để biết thêm chi tiết.

<a id="security-and-privacy"></a>

## Bảo mật và quyền riêng tư

Snapzy không chạy trong sandbox và chạy với quyền của tài khoản người dùng đã mở nó. Ứng dụng bật Hardened Runtime của macOS, được ký bằng Developer ID và notarize bởi Apple; library validation vẫn được bật, nên chỉ code do Snapzy hoặc Apple ký mới được nạp. Ảnh chụp và bản ghi được lưu cục bộ, và chỉ được tải lên AWS S3, Cloudflare R2 hoặc Google Drive của chính bạn khi bạn chủ động thực hiện. OCR tích hợp dùng Apple Vision ngay trên máy; nếu bạn cấu hình một endpoint OCR tùy chỉnh tương thích OpenAI, yêu cầu OCR sẽ kèm ảnh chụp và được gửi tới endpoint đó. Snapzy không thu thập dữ liệu telemetry.

Thông tin đăng nhập cloud, OAuth token và API key của OCR tùy chỉnh chỉ được lưu trong Chuỗi khóa (Keychain) của macOS. Mật khẩu bảo vệ thông tin đăng nhập cloud (tùy chọn) được băm SHA-256 và không bao giờ được lưu dưới dạng văn bản thô. Thông tin đăng nhập cloud chỉ có thể chuyển sang máy khác qua thao tác export/import thủ công được mã hóa bằng passphrase, còn API key của OCR tùy chỉnh không có trong file export cấu hình lẫn file export thông tin đăng nhập. File cấu hình TOML di động chỉ chứa các tùy chọn; không gồm secret, lịch sử chụp và tải lên, cache, danh sách ứng dụng đã được chấp thuận dùng CLI, và security-scoped bookmark. Xem [SECURITY.md](SECURITY.md) để biết chi tiết các yêu cầu mạng và toàn bộ chính sách bảo mật, và [hướng dẫn cấu hình](docs/CONFIGURATION.md) cho phần thiết lập di động.

Để báo cáo lỗ hổng, hãy dùng [GitHub Security Advisory](https://github.com/duongductrong/Snapzy/security/advisories/new) hoặc liên hệ riêng với maintainer. Xem [SECURITY.md](SECURITY.md) để biết cách báo cáo.

<a id="more-details"></a>

## Tài liệu chi tiết

Tài liệu chi tiết hiện chỉ có bằng tiếng Anh.

- [Chụp màn hình và OCR](docs/CAPTURE.md) · [Chụp cuộn](docs/SCROLLING_CAPTURE.md) · [Quay màn hình](docs/RECORDING.md)
- [Chú thích](docs/ANNOTATE.md) · [Trình sửa video](docs/VIDEO_EDITOR.md) · [Truy cập nhanh](docs/QUICK_ACCESS.md) · [Lịch sử](docs/HISTORY.md)
- [Tải lên cloud](docs/CLOUD.md) · [Phím tắt và URL scheme](docs/SHORTCUTS.md) · [CLI](docs/CLI.md)
- [Cấu hình và tùy chọn](docs/CONFIGURATION.md) · [Tham chiếu tùy chọn](docs/PREFERENCES.md) · [Cập nhật và chẩn đoán](docs/UPDATES.md)
- [Phát triển](docs/DEVELOPMENT.md) · [Build và đóng gói](docs/BUILD.md) · [Bản đồ tài liệu](docs/README.md)
- [Kết quả và phương pháp benchmark OCR](docs/OCR_BENCHMARK.md)

<a id="contributing"></a>

## Đóng góp

Mọi đóng góp đều được hoan nghênh. Hãy đọc [CONTRIBUTING.md](CONTRIBUTING.md) trước khi mở pull request.

<a id="contributors"></a>

## Người đóng góp

Cảm ơn tất cả những người đã đóng góp cho Snapzy!

<a href="https://github.com/duongductrong/Snapzy/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=duongductrong/Snapzy" />
</a>

<a id="featured-on"></a>

## Được giới thiệu trên

<p>
  <a href="https://www.producthunt.com/products/snapzy?embed=true&amp;utm_source=badge-featured&amp;utm_medium=badge&amp;utm_campaign=badge-snapzy" target="_blank" rel="noopener noreferrer"><img alt="Snapzy - Think CleanShot X, but open-source and developer-friendly | Product Hunt" width="250" height="54" src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1097629&amp;theme=light&amp;t=1773585048784"></a>
  <a href="https://unikorn.vn/p/snapzy?ref=embed-snapzy" target="_blank"><img src="https://unikorn.vn/api/widgets/badge/snapzy?theme=light" alt="Snapzy trên Unikorn.vn" style="width: 250px; height: 54px;" width="250" height="54" /></a>
</p>

<a id="star-history"></a>

## Lịch sử Star

<a href="https://www.star-history.com/?repos=duongductrong%2FSnapzy&type=date&logscale=&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/image?repos=duongductrong/Snapzy&type=date&theme=dark&logscale&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/image?repos=duongductrong/Snapzy&type=date&logscale&legend=top-left" />
   <img alt="Biểu đồ lịch sử Star" src="https://api.star-history.com/image?repos=duongductrong/Snapzy&type=date&logscale&legend=top-left" />
 </picture>
</a>

<a id="acknowledgments"></a>

## Lời cảm ơn

Snapzy lấy cảm hứng từ [CleanShot X](https://cleanshot.com/), một ứng dụng chụp và quay màn hình nâng cao dành cho macOS.

<a id="license"></a>

## Giấy phép

Giấy phép BSD 3-Clause. Xem [LICENSE](LICENSE).
