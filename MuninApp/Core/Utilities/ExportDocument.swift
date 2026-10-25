import SwiftUI
import UniformTypeIdentifiers

/// A file to save with `fileExporter`: an export's data, type and suggested name.
nonisolated struct ExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText, .plainText]

    /// The file's contents.
    let data: Data
    /// The file's type, which sets its extension.
    let contentType: UTType
    /// The suggested file name, without extension.
    let filename: String

    /// Creates a document to save.
    init(data: Data, contentType: UTType, filename: String) {
        self.data = data
        self.contentType = contentType
        self.filename = filename
    }

    /// Required by `FileDocument`; exports are never opened.
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        contentType = configuration.contentType
        filename = configuration.file.filename ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
