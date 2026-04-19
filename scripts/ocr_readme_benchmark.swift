//
//  ocr_readme_benchmark.swift
//  Snapzy
//
//  Reproducible OCR benchmark used for README transparency notes.
//
//  Run from repository root with:
//  swiftc -o /tmp/snapzy-ocr-readme-benchmark \
//    scripts/ocr_readme_benchmark.swift \
//    Snapzy/Services/Media/OCRService.swift \
//    Snapzy/Services/Media/OCR/OCRRequest.swift \
//    Snapzy/Services/Media/OCR/OCRResult.swift \
//    Snapzy/Services/Media/OCR/VisionOCRProfile.swift \
//    Snapzy/Services/Media/OCR/OCRBenchmarkMetrics.swift \
//    Snapzy/Services/Media/OCR/OCRBenchmarkHarness.swift \
//    Snapzy/Shared/Localization/AppLanguageManager.swift
//
//  /tmp/snapzy-ocr-readme-benchmark
//

import AppKit
import Foundation

enum DiagnosticLevel {
  case debug
  case info
  case warning
  case error
}

enum DiagnosticCategory {
  case ocr
}

final class DiagnosticLogger {
  static let shared = DiagnosticLogger()

  func log(
    _ level: DiagnosticLevel,
    _ category: DiagnosticCategory,
    _ message: String,
    context: [String: String] = [:]
  ) {}

  func logError(
    _ category: DiagnosticCategory,
    _ error: Error,
    _ message: String,
    context: [String: String] = [:]
  ) {}
}

enum L10n {
  enum OCR {
    static let imageConversionFailed = "imageConversionFailed"
    static let noTextFound = "noTextFound"

    static func recognitionFailed(_ message: String) -> String {
      "recognitionFailed: \(message)"
    }
  }
}

enum AppLanguageManager {
  static func normalizedLanguageIdentifier(from identifier: String?) -> String? {
    guard let identifier, !identifier.isEmpty else { return nil }
    return normalizedIdentifier(from: identifier)
  }

  private static func normalizedIdentifier(from identifier: String) -> String? {
    let normalized = identifier.lowercased()

    if normalized.contains("hant") || normalized.hasPrefix("zh-tw") || normalized.hasPrefix("zh-hk") || normalized.hasPrefix("zh-mo") {
      return "zh-Hant"
    }

    if normalized.contains("hans") || normalized.hasPrefix("zh-cn") || normalized.hasPrefix("zh-sg") {
      return "zh-Hans"
    }

    let prefixMap: [(prefix: String, identifier: String)] = [
      ("en", "en"),
      ("vi", "vi"),
      ("es", "es"),
      ("ja", "ja"),
      ("ko", "ko"),
      ("ru", "ru"),
      ("fr", "fr"),
      ("de", "de"),
    ]

    for entry in prefixMap where normalized.hasPrefix(entry.prefix) {
      return entry.identifier
    }

    return nil
  }
}

private struct CorpusEntry {
  let languageIdentifier: String
  let text: String
}

private struct RenderStyle {
  let name: String
  let fontSize: CGFloat
  let fontWeight: NSFont.Weight
  let backgroundColor: NSColor
  let textColor: NSColor
}

@main
struct OCRReadmeBenchmark {
  static func main() async {
    let corpus = benchmarkCorpus()
    let styles = benchmarkStyles()
    let cases = corpus.flatMap { entry in
      styles.compactMap { style -> OCRBenchmarkCase? in
        guard let image = renderImage(text: entry.text, style: style) else { return nil }
        return OCRBenchmarkCase(
          languageIdentifier: entry.languageIdentifier,
          expectedText: entry.text,
          request: OCRRequest(
            image: image,
            preferredLanguageIdentifier: entry.languageIdentifier,
            contentType: .interfaceText
          )
        )
      }
    }

    let summaries = await OCRBenchmarkHarness.run(cases: cases) { request in
      try await OCRService.shared.recognize(request)
    }

    print("OCR README benchmark corpus")
    print("- languages: \(Set(corpus.map(\.languageIdentifier)).count)")
    print("- samples per language: \(styles.count * 3)")
    print("- total samples: \(cases.count)")
    print("- corpus type: clean synthetic wrapped UI/article text")
    print("")
    print("| Language | Samples | Char Accuracy | Exact Match | No Output | Avg Confidence | Avg Latency |")
    print("| --- | ---: | ---: | ---: | ---: | ---: | ---: |")

    for summary in summaries {
      let latencyText = String(format: "%.0f ms", summary.averageLatencyMs)
      print(
        "| \(displayName(for: summary.languageIdentifier)) | \(summary.sampleCount) | " +
        "\(percent(summary.averageCharacterAccuracy)) | \(percent(summary.exactMatchRate)) | " +
        "\(percent(summary.noOutputRate)) | \(percent(summary.averageConfidence)) | " +
        "\(latencyText) |"
      )
    }
  }

  private static func benchmarkCorpus() -> [CorpusEntry] {
    [
      CorpusEntry(languageIdentifier: "en", text: "Snapzy keeps screenshots readable, searchable, and ready to share across your team."),
      CorpusEntry(languageIdentifier: "en", text: "Review notes before export so everyone copies the same clean text from the capture."),
      CorpusEntry(languageIdentifier: "en", text: "Fast OCR helps when release notes, code snippets, and settings panels need to be copied quickly."),

      CorpusEntry(languageIdentifier: "vi", text: "Snapzy giúp trích xuất văn bản rõ ràng để bạn sao chép ghi chú từ ảnh chụp màn hình nhanh hơn."),
      CorpusEntry(languageIdentifier: "vi", text: "Khi cần chia sẻ hướng dẫn nội bộ, OCR chính xác sẽ giảm rất nhiều thời gian chỉnh sửa thủ công."),
      CorpusEntry(languageIdentifier: "vi", text: "Các khung cài đặt, đoạn mô tả dài và tiêu đề có dấu đều nên được giữ nguyên nội dung sau khi nhận dạng."),

      CorpusEntry(languageIdentifier: "zh-Hans", text: "Snapzy 现在会优先保留正文内容，方便你直接复制截图里的长段落和标题。"),
      CorpusEntry(languageIdentifier: "zh-Hans", text: "如果一张截图里有多段说明文字，OCR 结果应该尽量保持自然分段与正确标点。"),
      CorpusEntry(languageIdentifier: "zh-Hans", text: "准确的中文识别对于整理笔记、产品说明和界面文案都非常重要。"),

      CorpusEntry(languageIdentifier: "zh-Hant", text: "Snapzy 現在會優先保留正文內容，方便你直接複製截圖裡的長段落和標題。"),
      CorpusEntry(languageIdentifier: "zh-Hant", text: "如果一張截圖裡有多段說明文字，OCR 結果應該盡量保持自然分段與正確標點。"),
      CorpusEntry(languageIdentifier: "zh-Hant", text: "準確的中文辨識對整理筆記、產品說明和介面文案都非常重要。"),

      CorpusEntry(languageIdentifier: "es", text: "Snapzy extrae texto limpio para que copiar instrucciones desde una captura sea un paso rápido y fiable."),
      CorpusEntry(languageIdentifier: "es", text: "Cuando una pantalla contiene varios párrafos, el OCR debe mantener una lectura natural y coherente."),
      CorpusEntry(languageIdentifier: "es", text: "Los títulos, números y signos de puntuación también importan cuando compartes documentación interna."),

      CorpusEntry(languageIdentifier: "ja", text: "Snapzy は長い説明文や見出しをそのままコピーしやすいように、読みやすい OCR を目指しています。"),
      CorpusEntry(languageIdentifier: "ja", text: "複数の段落があるスクリーンショットでも、自然な流れで文章を取り出せることが大切です。"),
      CorpusEntry(languageIdentifier: "ja", text: "設定画面、メモ、リリースノートの文字が正確に読めると作業がかなり速くなります。"),

      CorpusEntry(languageIdentifier: "ko", text: "Snapzy 는 긴 설명 문장과 제목도 자연스럽게 복사할 수 있도록 읽기 쉬운 OCR 결과를 목표로 합니다."),
      CorpusEntry(languageIdentifier: "ko", text: "여러 단락이 있는 화면이라도 문맥이 이어지도록 텍스트를 안정적으로 추출하는 것이 중요합니다."),
      CorpusEntry(languageIdentifier: "ko", text: "설정 화면, 메모, 릴리스 노트에 있는 한글 문장을 정확하게 읽어야 작업 속도가 빨라집니다."),

      CorpusEntry(languageIdentifier: "ru", text: "Snapzy помогает быстро копировать длинные заметки и заголовки со скриншотов без ручного перепечатывания."),
      CorpusEntry(languageIdentifier: "ru", text: "Если на изображении несколько абзацев, OCR должен сохранять естественный порядок чтения."),
      CorpusEntry(languageIdentifier: "ru", text: "Точные цифры, знаки препинания и подписи важны для внутренних инструкций и релизных заметок."),

      CorpusEntry(languageIdentifier: "fr", text: "Snapzy extrait un texte propre pour que les captures d’écran deviennent faciles à relire et à partager."),
      CorpusEntry(languageIdentifier: "fr", text: "Quand une image contient plusieurs paragraphes, l’OCR doit préserver une lecture naturelle et stable."),
      CorpusEntry(languageIdentifier: "fr", text: "Les titres, les chiffres et la ponctuation comptent aussi pour les notes produit et la documentation."),

      CorpusEntry(languageIdentifier: "de", text: "Snapzy extrahiert sauberen Text, damit lange Hinweise und Überschriften schnell aus Screenshots kopiert werden können."),
      CorpusEntry(languageIdentifier: "de", text: "Wenn ein Bild mehrere Absätze enthält, sollte die OCR eine natürliche und konsistente Lesereihenfolge behalten."),
      CorpusEntry(languageIdentifier: "de", text: "Auch Zahlen, Satzzeichen und UI-Bezeichnungen müssen für interne Dokumentation zuverlässig erkannt werden.")
    ]
  }

  private static func benchmarkStyles() -> [RenderStyle] {
    [
      RenderStyle(
        name: "light-16-regular",
        fontSize: 16,
        fontWeight: .regular,
        backgroundColor: NSColor(calibratedWhite: 0.985, alpha: 1),
        textColor: NSColor(calibratedWhite: 0.08, alpha: 1)
      ),
      RenderStyle(
        name: "light-19-semibold",
        fontSize: 19,
        fontWeight: .semibold,
        backgroundColor: NSColor(calibratedWhite: 0.985, alpha: 1),
        textColor: NSColor(calibratedWhite: 0.08, alpha: 1)
      ),
      RenderStyle(
        name: "dark-16-regular",
        fontSize: 16,
        fontWeight: .regular,
        backgroundColor: NSColor(calibratedWhite: 0.12, alpha: 1),
        textColor: NSColor(calibratedWhite: 0.96, alpha: 1)
      ),
      RenderStyle(
        name: "dark-19-semibold",
        fontSize: 19,
        fontWeight: .semibold,
        backgroundColor: NSColor(calibratedWhite: 0.12, alpha: 1),
        textColor: NSColor(calibratedWhite: 0.96, alpha: 1)
      )
    ]
  }

  private static func renderImage(text: String, style: RenderStyle) -> CGImage? {
    let canvasWidth: CGFloat = 820
    let textInset: CGFloat = 44
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineBreakMode = .byWordWrapping
    paragraphStyle.lineSpacing = style.fontSize * 0.3

    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: style.fontSize, weight: style.fontWeight),
      .foregroundColor: style.textColor,
      .paragraphStyle: paragraphStyle
    ]

    let attributedText = NSAttributedString(string: text, attributes: attributes)
    let textRect = NSRect(x: textInset, y: textInset, width: canvasWidth - (textInset * 2), height: 1000)
    let measuredBounds = attributedText.boundingRect(
      with: textRect.size,
      options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    let canvasHeight = max(220, ceil(measuredBounds.height + (textInset * 2)))

    let image = NSImage(size: NSSize(width: canvasWidth, height: canvasHeight))
    image.lockFocus()
    style.backgroundColor.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)).fill()

    attributedText.draw(
      with: NSRect(x: textInset, y: textInset, width: canvasWidth - (textInset * 2), height: canvasHeight - (textInset * 2)),
      options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    image.unlockFocus()

    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
  }

  private static func displayName(for identifier: String) -> String {
    switch identifier {
    case "en": return "English"
    case "vi": return "Vietnamese"
    case "zh-Hans": return "Simplified Chinese"
    case "zh-Hant": return "Traditional Chinese"
    case "es": return "Spanish"
    case "ja": return "Japanese"
    case "ko": return "Korean"
    case "ru": return "Russian"
    case "fr": return "French"
    case "de": return "German"
    default: return identifier
    }
  }

  private static func percent(_ value: Double) -> String {
    String(format: "%.1f%%", value * 100)
  }
}
