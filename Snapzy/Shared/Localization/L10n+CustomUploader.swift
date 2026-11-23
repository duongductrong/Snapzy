//
//  L10n+CustomUploader.swift
//  Snapzy
//
//  Strings for custom HTTP uploaders: errors, .sxcu import warnings and the Settings editor.
//

import Foundation

extension L10n {
  nonisolated enum CustomUploader {
    static func duplicateName(_ name: String) -> String {
      format(
        "cloud.custom-uploader.duplicate-name",
        defaultValue: "%@ Copy",
        comment: "Name of a duplicated custom uploader; %@ is the original name",
        name
      )
    }
    static let importedDefaultName = string(
      "cloud.custom-uploader.imported-default-name",
      defaultValue: "Imported Uploader",
      comment: "Name given to an imported ShareX uploader that has no name"
    )
    static let errorUploaderNotFound = string(
      "cloud.custom-uploader.error.uploader-not-found",
      defaultValue: "The selected custom uploader no longer exists. Choose another one in Settings > Cloud.",
      comment: "Error when the custom uploader chosen for uploads was deleted"
    )
    static let errorInvalidRequestURL = string(
      "cloud.custom-uploader.error.invalid-request-url",
      defaultValue: "The request URL must be an http or https address.",
      comment: "Error when a custom uploader's request URL is not a valid web address"
    )
    static func errorUnresolvedSecret(_ name: String) -> String {
      format(
        "cloud.custom-uploader.error.unresolved-secret",
        defaultValue: "The secret “%@” wasn’t found. Add it in Settings before uploading.",
        comment: "Error when a {secret:NAME} reference has no stored value; %@ is the secret name",
        name
      )
    }
    static func errorUnsupportedToken(_ token: String) -> String {
      format(
        "cloud.custom-uploader.error.unsupported-token",
        defaultValue: "Unsupported template token: %@",
        comment: "Error for a template token Snapzy does not support; %@ is the token, e.g. {random:a|b}",
        token
      )
    }
    static func errorInvalidRegex(_ pattern: String) -> String {
      format(
        "cloud.custom-uploader.error.invalid-regex",
        defaultValue: "Invalid regular expression: %@",
        comment: "Error for a malformed regex in a custom uploader; %@ is the pattern",
        pattern
      )
    }
    static func errorInvalidJSONPath(_ path: String) -> String {
      format(
        "cloud.custom-uploader.error.invalid-json-path",
        defaultValue: "Invalid JSON path: %@",
        comment: "Error for a malformed JSON path such as data..url; %@ is the path",
        path
      )
    }
    static func errorValueNotFound(_ field: String) -> String {
      format(
        "cloud.custom-uploader.error.value-not-found",
        defaultValue: "The response has no value for %@.",
        comment: "Error when an extractor finds nothing in the server response; %@ is a field name such as URL",
        field
      )
    }
    static func errorInvalidResultURL(_ field: String) -> String {
      format(
        "cloud.custom-uploader.error.invalid-result-url",
        defaultValue: "The %@ in the response isn’t an http or https link.",
        comment: "Error when the extracted link is not a web URL (e.g. file: or javascript:); %@ is a field name such as URL",
        field
      )
    }
    static func errorLimitReached(_ count: Int) -> String {
      format(
        "cloud.custom-uploader.error.limit-reached",
        defaultValue: "You can have up to %lld custom uploaders.",
        comment: "Error when adding more custom uploaders than allowed; %lld is the limit",
        count
      )
    }
    static let errorInvalidImportFile = string(
      "cloud.custom-uploader.error.invalid-import-file",
      defaultValue: "This file isn’t a valid ShareX custom uploader (.sxcu).",
      comment: "Error when an imported .sxcu/.json file can't be read"
    )
    static let errorTransferUnsupported = string(
      "cloud.custom-uploader.error.transfer-unsupported",
      defaultValue: "Custom uploaders can’t be exported in an encrypted credentials archive.",
      comment: "Error when exporting cloud credentials while a custom uploader is the Cloud provider"
    )
    static func warningUnsupportedToken(_ token: String, field: String) -> String {
      format(
        "cloud.custom-uploader.warning.unsupported-token",
        defaultValue: "%1$@ in %2$@ isn’t supported and will fail at upload time.",
        comment: "Import warning; %1$@ is a template token, %2$@ is the ShareX field name (e.g. RequestURL)",
        token, field
      )
    }
    static func warningUnsupportedBody(_ body: String) -> String {
      format(
        "cloud.custom-uploader.warning.unsupported-body",
        defaultValue: "Body type “%@” isn’t supported; multipart form data is used instead.",
        comment: "Import warning; %@ is the ShareX body type, e.g. JSON",
        body
      )
    }
    static func warningBodyWithoutFile(_ body: String) -> String {
      format(
        "cloud.custom-uploader.warning.body-without-file",
        defaultValue: "Body type “%@” sends form fields only, without the file.",
        comment: "Import warning; %@ is the ShareX body type, e.g. FormURLEncoded",
        body
      )
    }
    static func warningUnsupportedMethod(_ method: String) -> String {
      format(
        "cloud.custom-uploader.warning.unsupported-method",
        defaultValue: "Method “%@” isn’t supported; POST is used instead.",
        comment: "Import warning; %@ is the HTTP method from the file, e.g. GET",
        method
      )
    }
    static func warningIgnoredField(_ field: String) -> String {
      format(
        "cloud.custom-uploader.warning.ignored-field",
        defaultValue: "The “%@” field is ignored.",
        comment: "Import warning; %@ is a ShareX field name that Snapzy does not use",
        field
      )
    }
    static let sectionTitle = string(
      "cloud.custom-uploader.section-title",
      defaultValue: "Custom Uploaders",
      comment: "Cloud settings section listing custom HTTP uploaders"
    )
    static let sectionDescription = string(
      "cloud.custom-uploader.section-description",
      defaultValue: "Upload to your own server or any ShareX-compatible host. Credentials are referenced as {secret:NAME} and kept in the Keychain.",
      comment: "Explains custom uploaders; {secret:NAME} is literal syntax and must not be translated"
    )
    static let activeUploader = string(
      "cloud.custom-uploader.active-uploader",
      defaultValue: "Active uploader",
      comment: "Picker label for the custom uploader used by Cloud uploads"
    )
    static let noUploaderSelected = string(
      "cloud.custom-uploader.no-uploader-selected",
      defaultValue: "No uploader selected",
      comment: "Shown when no custom uploader is chosen"
    )
    static let emptyState = string(
      "cloud.custom-uploader.empty-state",
      defaultValue: "No custom uploaders yet. Create one or import a ShareX .sxcu file.",
      comment: "Empty list message for custom uploaders"
    )
    static let newUploader = string(
      "cloud.custom-uploader.new-uploader",
      defaultValue: "New",
      comment: "Button that creates a new custom uploader"
    )
    static let duplicate = string(
      "cloud.custom-uploader.duplicate",
      defaultValue: "Duplicate",
      comment: "Button that copies the selected custom uploader"
    )
    static let importSXCU = string(
      "cloud.custom-uploader.import-sxcu",
      defaultValue: "Import .sxcu…",
      comment: "Button that imports a ShareX custom uploader file"
    )
    static let importPanelTitle = string(
      "cloud.custom-uploader.import-panel-title",
      defaultValue: "Import ShareX Uploader",
      comment: "Title of the open panel for .sxcu files"
    )
    static let importPanelMessage = string(
      "cloud.custom-uploader.import-panel-message",
      defaultValue: "Choose a ShareX custom uploader file (.sxcu or .json).",
      comment: "Message of the open panel for .sxcu files"
    )
    static func importedTitle(_ name: String) -> String {
      format(
        "cloud.custom-uploader.imported-title",
        defaultValue: "Imported “%@”",
        comment: "Title of the sheet shown after importing a .sxcu file; %@ is the uploader name",
        name
      )
    }
    static let importWarningsHeader = string(
      "cloud.custom-uploader.import-warnings-header",
      defaultValue: "Some settings need attention:",
      comment: "Header above the list of .sxcu import warnings"
    )
    static let secretCandidatesHeader = string(
      "cloud.custom-uploader.secret-candidates-header",
      defaultValue: "These fields look like credentials. Store them as secrets so the values live in the Keychain instead of the uploader.",
      comment: "Explains the Store as Secret option after an import"
    )
    static let storeAsSecret = string(
      "cloud.custom-uploader.store-as-secret",
      defaultValue: "Store as Secret",
      comment: "Button that moves a credential-looking value into the secret store"
    )
    static func storedAsSecret(_ reference: String) -> String {
      format(
        "cloud.custom-uploader.stored-as-secret",
        defaultValue: "Stored as %@",
        comment: "Confirmation after storing a secret; %@ is the reference such as {secret:ZIPLINE_AUTHORIZATION}",
        reference
      )
    }
    static let secretName = string(
      "cloud.custom-uploader.secret-name",
      defaultValue: "Secret name",
      comment: "Field label for the name of a stored secret"
    )
    static let invalidSecretName = string(
      "cloud.custom-uploader.invalid-secret-name",
      defaultValue: "Use 1–64 letters, digits, _, - or .",
      comment: "Validation message for a secret name"
    )
    static let locationHeader = string(
      "cloud.custom-uploader.location.header",
      defaultValue: "Header",
      comment: "Where a credential was found: an HTTP header"
    )
    static let locationQuery = string(
      "cloud.custom-uploader.location.query",
      defaultValue: "Query parameter",
      comment: "Where a credential was found: a URL query parameter"
    )
    static let locationBodyField = string(
      "cloud.custom-uploader.location.body-field",
      defaultValue: "Form field",
      comment: "Where a credential was found: a form field in the request body"
    )
    static func deleteConfirmTitle(_ name: String) -> String {
      format(
        "cloud.custom-uploader.delete-confirm-title",
        defaultValue: "Delete “%@”?",
        comment: "Delete confirmation title; %@ is the uploader name",
        name
      )
    }
    static let deleteConfirmMessage = string(
      "cloud.custom-uploader.delete-confirm-message",
      defaultValue: "Cloud uploads and automations that use this uploader will fail until you choose another one.",
      comment: "Delete confirmation message for a custom uploader"
    )
    static let editorNewTitle = string(
      "cloud.custom-uploader.editor.new-title",
      defaultValue: "New Custom Uploader",
      comment: "Title of the editor sheet when creating an uploader"
    )
    static let editorEditTitle = string(
      "cloud.custom-uploader.editor.edit-title",
      defaultValue: "Edit Custom Uploader",
      comment: "Title of the editor sheet when editing an uploader"
    )
    static let requestSection = string(
      "cloud.custom-uploader.editor.request-section",
      defaultValue: "Request",
      comment: "Editor section for the HTTP request"
    )
    static let method = string(
      "cloud.custom-uploader.editor.method",
      defaultValue: "Method",
      comment: "Editor field: HTTP method"
    )
    static let requestURL = string(
      "cloud.custom-uploader.editor.request-url",
      defaultValue: "Request URL",
      comment: "Editor field: request URL"
    )
    static let headers = string(
      "cloud.custom-uploader.editor.headers",
      defaultValue: "Headers",
      comment: "Editor list: HTTP headers"
    )
    static let queryParameters = string(
      "cloud.custom-uploader.editor.query-parameters",
      defaultValue: "Query parameters",
      comment: "Editor list: URL query parameters"
    )
    static let bodySection = string(
      "cloud.custom-uploader.editor.body-section",
      defaultValue: "Body",
      comment: "Editor section for the request body"
    )
    static let bodyType = string(
      "cloud.custom-uploader.editor.body-type",
      defaultValue: "Body type",
      comment: "Editor picker: request body type"
    )
    static let bodyMultipart = string(
      "cloud.custom-uploader.editor.body-multipart",
      defaultValue: "Multipart form data",
      comment: "Body type: multipart/form-data with the file"
    )
    static let bodyBinary = string(
      "cloud.custom-uploader.editor.body-binary",
      defaultValue: "Binary file",
      comment: "Body type: the raw file bytes"
    )
    static let bodyFormURLEncoded = string(
      "cloud.custom-uploader.editor.body-form-url-encoded",
      defaultValue: "URL-encoded form (no file)",
      comment: "Body type: application/x-www-form-urlencoded fields without the file"
    )
    static let fileField = string(
      "cloud.custom-uploader.editor.file-field",
      defaultValue: "File field",
      comment: "Editor field: multipart form field name that carries the file"
    )
    static let formFields = string(
      "cloud.custom-uploader.editor.form-fields",
      defaultValue: "Form fields",
      comment: "Editor list: extra form fields"
    )
    static let addRow = string(
      "cloud.custom-uploader.editor.add-row",
      defaultValue: "Add",
      comment: "Button adding a name/value row"
    )
    static let removeRow = string(
      "cloud.custom-uploader.editor.remove-row",
      defaultValue: "Remove",
      comment: "Accessibility label of the button removing a name/value row"
    )
    static let keyPlaceholder = string(
      "cloud.custom-uploader.editor.key-placeholder",
      defaultValue: "Name",
      comment: "Placeholder for the name column of a name/value row"
    )
    static let valuePlaceholder = string(
      "cloud.custom-uploader.editor.value-placeholder",
      defaultValue: "Value",
      comment: "Placeholder for the value column of a name/value row"
    )
    static let responseSection = string(
      "cloud.custom-uploader.editor.response-section",
      defaultValue: "Response",
      comment: "Editor section for reading the server response"
    )
    static let responseURL = string(
      "cloud.custom-uploader.editor.response-url",
      defaultValue: "URL",
      comment: "Editor field: how the public link is read from the response"
    )
    static let deletionURL = string(
      "cloud.custom-uploader.editor.deletion-url",
      defaultValue: "Deletion URL",
      comment: "Editor field: how the deletion link is read from the response"
    )
    static let errorMessage = string(
      "cloud.custom-uploader.editor.error-message",
      defaultValue: "Error message",
      comment: "Editor field: how the error message is read from a failed response"
    )
    static let extractorNone = string(
      "cloud.custom-uploader.editor.extractor-none",
      defaultValue: "Not used",
      comment: "Extractor option: this optional value is not read"
    )
    static let extractorPlainText = string(
      "cloud.custom-uploader.editor.extractor-plain-text",
      defaultValue: "Whole response",
      comment: "Extractor option: the whole response body"
    )
    static let extractorJSONPath = string(
      "cloud.custom-uploader.editor.extractor-json-path",
      defaultValue: "JSON path",
      comment: "Extractor option: JSON path such as data.url"
    )
    static let extractorRegex = string(
      "cloud.custom-uploader.editor.extractor-regex",
      defaultValue: "Regular expression",
      comment: "Extractor option: regex with first capture group"
    )
    static let extractorTemplate = string(
      "cloud.custom-uploader.editor.extractor-template",
      defaultValue: "Template",
      comment: "Extractor option: template mixing text and tokens"
    )
    static let timeout = string(
      "cloud.custom-uploader.editor.timeout",
      defaultValue: "Timeout (seconds)",
      comment: "Editor field: request timeout"
    )
    static let syntaxHint = string(
      "cloud.custom-uploader.editor.syntax-hint",
      defaultValue: "Request fields support {filename} and {secret:NAME}. Response templates support {json:path}, {regex:pattern|group}, {response}, {header:name} and {filename}.",
      comment: "Syntax help in the editor; everything in braces is literal syntax and must not be translated"
    )
    static let test = string(
      "cloud.custom-uploader.test.button",
      defaultValue: "Test",
      comment: "Button that sends a test upload with the editor's settings"
    )
    static let testing = string(
      "cloud.custom-uploader.test.in-progress",
      defaultValue: "Testing…",
      comment: "Shown while a test upload runs"
    )
    static let testDescription = string(
      "cloud.custom-uploader.test.description",
      defaultValue: "Uploads a 1×1 PNG with these settings.",
      comment: "Explains what the Test button sends"
    )
    static func testStatus(_ code: Int) -> String {
      format(
        "cloud.custom-uploader.test.status",
        defaultValue: "HTTP %lld",
        comment: "Test result: HTTP status code",
        code
      )
    }
    static let testResponseBody = string(
      "cloud.custom-uploader.test.response-body",
      defaultValue: "Response body",
      comment: "Test result: label above the raw response"
    )
    static let testEmptyBody = string(
      "cloud.custom-uploader.test.empty-body",
      defaultValue: "(empty)",
      comment: "Test result: the server returned no body"
    )
    static let testExtractedURL = string(
      "cloud.custom-uploader.test.extracted-url",
      defaultValue: "Extracted URL",
      comment: "Test result: label for the link read from the response"
    )
    static let testError = string(
      "cloud.custom-uploader.test.error",
      defaultValue: "Error",
      comment: "Test result: label for the error message"
    )
    static func warningRemovedSecret(_ token: String, _ field: String) -> String {
      format(
        "cloud.custom-uploader.warning.removed-secret",
        defaultValue: "%1$@ in %2$@ was removed: an imported file can’t use your saved secrets. Add your own key with Store as Secret or in the editor.",
        comment: "Import warning; %1$@ is a {secret:NAME} token, %2$@ is the ShareX field name",
        token, field
      )
    }
  }
}
