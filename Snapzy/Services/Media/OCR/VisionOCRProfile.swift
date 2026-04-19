//
//  VisionOCRProfile.swift
//  Snapzy
//
//  Language-aware Vision OCR profiles tuned for screenshot text.
//

import Foundation
import Vision

struct VisionOCRProfile {
  let id: String
  let recognitionLanguages: [String]
  let customWords: [String]
  let usesLanguageCorrection: Bool
  let automaticallyDetectsLanguage: Bool
  let minimumTextHeight: Float?
  let minimumAcceptableConfidence: Float
  let prefersCJKContent: Bool

  static func resolve(for request: OCRRequest) -> VisionOCRProfile {
    if request.contentType == .code {
      return .code
    }

    switch AppLanguageManager.normalizedLanguageIdentifier(from: request.preferredLanguageIdentifier) {
    case "ja":
      return .japaneseInterface
    case "ko":
      return .koreanInterface
    case "zh-Hans":
      return .simplifiedChineseInterface
    case "zh-Hant":
      return .traditionalChineseInterface
    case "en":
      return .defaultInterface
    default:
      return request.contentType == .denseDocument ? .denseDocument : .defaultInterface
    }
  }

  static func recoveryProfiles(for request: OCRRequest, primary primaryProfile: VisionOCRProfile) -> [VisionOCRProfile] {
    switch primaryProfile.id {
    case englishInterface.id:
      return [defaultInterface, cjkRecovery, autoRecovery]
    case japaneseInterface.id, koreanInterface.id, simplifiedChineseInterface.id, traditionalChineseInterface.id:
      return [cjkRecovery, autoRecovery]
    case code.id:
      return [defaultInterface, autoRecovery]
    case defaultInterface.id:
      return [cjkRecovery, autoRecovery]
    default:
      if request.contentType == .denseDocument {
        return [cjkRecovery, autoRecovery]
      }
      return []
    }
  }

  static func enhancedRecoveryProfiles(for request: OCRRequest, primary primaryProfile: VisionOCRProfile) -> [VisionOCRProfile] {
    guard request.contentType != .code else { return [] }

    switch primaryProfile.id {
    case japaneseInterface.id, koreanInterface.id, simplifiedChineseInterface.id, traditionalChineseInterface.id:
      return [cjkRecovery, autoRecovery, defaultInterface]
    case denseDocument.id:
      return [autoRecovery, cjkRecovery, defaultInterface]
    default:
      return [cjkRecovery, autoRecovery]
    }
  }

  func configure(_ request: VNRecognizeTextRequest) {
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = usesLanguageCorrection
    if !recognitionLanguages.isEmpty {
      request.recognitionLanguages = recognitionLanguages
    }
    if !customWords.isEmpty {
      request.customWords = customWords
    }
    if let minimumTextHeight {
      request.minimumTextHeight = minimumTextHeight
    }
    if #available(macOS 13.0, *) {
      request.automaticallyDetectsLanguage = automaticallyDetectsLanguage
    }
  }
}

private extension VisionOCRProfile {
  static let sharedProductWords = [
    "Snapzy",
    "OCR",
    "Quick Access",
    "Annotate",
    "Preferences",
    "Export",
    "Shortcut",
    "Screenshot"
  ]

  static let defaultInterface = VisionOCRProfile(
    id: "default-interface",
    recognitionLanguages: [],
    customWords: sharedProductWords,
    usesLanguageCorrection: true,
    automaticallyDetectsLanguage: true,
    minimumTextHeight: 0.008,
    minimumAcceptableConfidence: 0.58,
    prefersCJKContent: false
  )

  static let englishInterface = VisionOCRProfile(
    id: "english-interface",
    recognitionLanguages: ["en-US"],
    customWords: sharedProductWords,
    usesLanguageCorrection: true,
    automaticallyDetectsLanguage: false,
    minimumTextHeight: 0.008,
    minimumAcceptableConfidence: 0.62,
    prefersCJKContent: false
  )

  static let japaneseInterface = VisionOCRProfile(
    id: "japanese-interface",
    recognitionLanguages: ["ja-JP", "en-US"],
    customWords: sharedProductWords + ["設定", "ショートカット", "書き出し", "画面", "選択"],
    usesLanguageCorrection: true,
    automaticallyDetectsLanguage: false,
    minimumTextHeight: 0.006,
    minimumAcceptableConfidence: 0.55,
    prefersCJKContent: true
  )

  static let koreanInterface = VisionOCRProfile(
    id: "korean-interface",
    recognitionLanguages: ["ko-KR", "en-US"],
    customWords: sharedProductWords + ["환경설정", "단축키", "내보내기", "화면", "선택"],
    usesLanguageCorrection: true,
    automaticallyDetectsLanguage: false,
    minimumTextHeight: 0.006,
    minimumAcceptableConfidence: 0.55,
    prefersCJKContent: true
  )

  static let simplifiedChineseInterface = VisionOCRProfile(
    id: "simplified-chinese-interface",
    recognitionLanguages: ["zh-Hans", "en-US"],
    customWords: sharedProductWords + ["偏好设置", "快捷键", "导出", "屏幕", "选区"],
    usesLanguageCorrection: true,
    automaticallyDetectsLanguage: false,
    minimumTextHeight: 0.006,
    minimumAcceptableConfidence: 0.55,
    prefersCJKContent: true
  )

  static let traditionalChineseInterface = VisionOCRProfile(
    id: "traditional-chinese-interface",
    recognitionLanguages: ["zh-Hant", "en-US"],
    customWords: sharedProductWords + ["偏好設定", "快捷鍵", "匯出", "螢幕", "選取"],
    usesLanguageCorrection: true,
    automaticallyDetectsLanguage: false,
    minimumTextHeight: 0.006,
    minimumAcceptableConfidence: 0.55,
    prefersCJKContent: true
  )

  static let denseDocument = VisionOCRProfile(
    id: "dense-document",
    recognitionLanguages: [],
    customWords: sharedProductWords,
    usesLanguageCorrection: true,
    automaticallyDetectsLanguage: true,
    minimumTextHeight: 0.005,
    minimumAcceptableConfidence: 0.52,
    prefersCJKContent: false
  )

  static let cjkRecovery = VisionOCRProfile(
    id: "cjk-recovery",
    recognitionLanguages: ["zh-Hans", "zh-Hant", "ja-JP", "ko-KR", "en-US"],
    customWords: sharedProductWords + [
      "偏好设置",
      "偏好設定",
      "快捷键",
      "快捷鍵",
      "导出",
      "匯出",
      "設定",
      "環境設定",
      "환경설정"
    ],
    usesLanguageCorrection: true,
    automaticallyDetectsLanguage: false,
    minimumTextHeight: 0.004,
    minimumAcceptableConfidence: 0.42,
    prefersCJKContent: true
  )

  static let autoRecovery = VisionOCRProfile(
    id: "auto-recovery",
    recognitionLanguages: [],
    customWords: sharedProductWords + [
      "偏好设置",
      "偏好設定",
      "快捷键",
      "快捷鍵",
      "复制",
      "貼上",
      "粘贴",
      "設定",
      "환경설정"
    ],
    usesLanguageCorrection: true,
    automaticallyDetectsLanguage: true,
    minimumTextHeight: 0.004,
    minimumAcceptableConfidence: 0.38,
    prefersCJKContent: false
  )

  static let code = VisionOCRProfile(
    id: "code",
    recognitionLanguages: ["en-US"],
    customWords: [
      "Snapzy",
      "OCRService",
      "QuickAccessSound",
      "captureOCR",
      "CGImage",
      "NSImage"
    ],
    usesLanguageCorrection: false,
    automaticallyDetectsLanguage: false,
    minimumTextHeight: 0.01,
    minimumAcceptableConfidence: 0.42,
    prefersCJKContent: false
  )
}
