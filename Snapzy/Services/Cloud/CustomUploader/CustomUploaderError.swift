//
//  CustomUploaderError.swift
//  Snapzy
//

import Foundation

nonisolated enum CustomUploaderError: LocalizedError, Equatable {
  case uploaderNotFound
  case invalidRequestURL
  case unresolvedSecret(String)
  case unsupportedToken(String)
  case invalidRegex(String)
  case invalidJSONPath(String)
  case valueNotFound(field: String)
  case invalidResultURL(field: String)
  case limitReached(Int)
  case invalidImportFile
  case transferUnsupported

  var errorDescription: String? {
    switch self {
    case .uploaderNotFound:
      return L10n.CustomUploader.errorUploaderNotFound
    case .invalidRequestURL:
      return L10n.CustomUploader.errorInvalidRequestURL
    case .unresolvedSecret(let name):
      return L10n.CustomUploader.errorUnresolvedSecret(name)
    case .unsupportedToken(let token):
      return L10n.CustomUploader.errorUnsupportedToken(token)
    case .invalidRegex(let pattern):
      return L10n.CustomUploader.errorInvalidRegex(pattern)
    case .invalidJSONPath(let path):
      return L10n.CustomUploader.errorInvalidJSONPath(path)
    case .valueNotFound(let field):
      return L10n.CustomUploader.errorValueNotFound(field)
    case .invalidResultURL(let field):
      return L10n.CustomUploader.errorInvalidResultURL(field)
    case .limitReached(let limit):
      return L10n.CustomUploader.errorLimitReached(limit)
    case .invalidImportFile:
      return L10n.CustomUploader.errorInvalidImportFile
    case .transferUnsupported:
      return L10n.CustomUploader.errorTransferUnsupported
    }
  }
}
