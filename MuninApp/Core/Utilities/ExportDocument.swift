import SwiftUI
import UniformTypeIdentifiers

/// A document that holds export data for saving with the `fileExporter` modifier.
nonisolated struct ExportDocument: FileDocument {
    /// The content types the document can hold.
    static let readableContentTypes: [UTType] = [.commaSeparatedText, .plainText]

    /// The file's contents.
    let data: Data
    /// The file's content type, which determines its extension.
    let contentType: UTType
    /// The suggested file name, without extension.
    let filename: String

    /// Creates a document with the given contents, type, and suggested file name.
    init(data: Data, contentType: UTType, filename: String) {
        self.data = data
        self.contentType = contentType
        self.filename = filename
    }

    /// Creates a document from a file.
    ///
    /// Required by `FileDocument`. The app never opens exported files.
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        contentType = configuration.contentType
        filename = configuration.file.filename ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
