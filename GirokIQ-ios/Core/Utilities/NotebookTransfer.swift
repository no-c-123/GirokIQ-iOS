import Foundation
import SwiftUI
internal import UniformTypeIdentifiers
import UIKit

extension UTType {
    static let girokIQNotebook = UTType(exportedAs: "com.girokiq.notebook", conformingTo: .data)
    static let girokIQFolder = UTType(exportedAs: "com.girokiq.folder", conformingTo: .data)
}

struct NotebookTransferPackage: Codable {
    var version: Int
    var notebook: NotebookTransferNotebook
    var pages: [NotebookTransferPage]
    var assets: [NotebookTransferAsset]

    init(
        version: Int,
        notebook: NotebookTransferNotebook,
        pages: [NotebookTransferPage],
        assets: [NotebookTransferAsset] = []
    ) {
        self.version = version
        self.notebook = notebook
        self.pages = pages
        self.assets = assets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        notebook = try container.decode(NotebookTransferNotebook.self, forKey: .notebook)
        pages = try container.decode([NotebookTransferPage].self, forKey: .pages)
        assets = try container.decodeIfPresent([NotebookTransferAsset].self, forKey: .assets) ?? []
    }
}

struct NotebookTransferNotebook: Codable {
    var name: String
    var canvasType: String
    var pageDimensions: PageDimensions?
    var backgroundPattern: String
    var backgroundColorHex: String
}

struct NotebookTransferPage: Codable {
    var title: String
    var pageIndex: Int
    var type: String
    var backgroundPattern: String
    var drawingData: Data?
    var elements: [CanvasElement]
}

struct NotebookTransferAsset: Codable, Hashable {
    var fileName: String
    var mimeType: String
    var data: Data
}

struct FolderTransferPackage: Codable {
    var version: Int
    var folder: FolderTransferFolder
    var notebooks: [NotebookTransferPackage]
}

struct FolderTransferFolder: Codable {
    var name: String
}

struct ExportedBinaryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .girokIQNotebook, .girokIQFolder, .pdf] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum NotebookTransferSupport {
    nonisolated private static let imagesDirectoryName = "Images"

    nonisolated private static func applicationSupportDirectory() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let imagesURL = baseURL.appendingPathComponent(imagesDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: imagesURL.path) {
            try? FileManager.default.createDirectory(
                at: imagesURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        return imagesURL
    }

    nonisolated private static func legacyDocumentsImageURL(for fileName: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
    }

    nonisolated private static func isCanvasImageFileName(_ fileName: String) -> Bool {
        let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        return UUID(uuidString: stem) != nil
    }

    nonisolated static func localImageURL(for fileName: String) -> URL {
        let destinationURL = applicationSupportDirectory().appendingPathComponent(fileName)
        let legacyURL = legacyDocumentsImageURL(for: fileName)

        if !FileManager.default.fileExists(atPath: destinationURL.path),
           FileManager.default.fileExists(atPath: legacyURL.path) {
            do {
                if !FileManager.default.fileExists(atPath: destinationURL.deletingLastPathComponent().path) {
                    try FileManager.default.createDirectory(
                        at: destinationURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                }
                try FileManager.default.moveItem(at: legacyURL, to: destinationURL)
            } catch {
                // Fall back to the old location for this read if the move fails.
                return legacyURL
            }
        }

        return destinationURL
    }

    static func mimeType(for fileName: String) -> String {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        switch ext {
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        case "heic", "heif": return "image/heic"
        default: return "image/jpeg"
        }
    }

    static func imageAssets(from pages: [NotebookTransferPage]) -> [NotebookTransferAsset] {
        var seen = Set<String>()
        var assets: [NotebookTransferAsset] = []

        for page in pages {
            for element in page.elements where element.type == "image" {
                guard let fileName = element.content, !fileName.isEmpty, !seen.contains(fileName) else { continue }
                let url = localImageURL(for: fileName)
                guard let data = try? Data(contentsOf: url) else { continue }
                assets.append(
                    NotebookTransferAsset(
                        fileName: fileName,
                        mimeType: mimeType(for: fileName),
                        data: data
                    )
                )
                seen.insert(fileName)
            }
        }

        return assets
    }

    static func writeImportedImageAsset(
        _ asset: NotebookTransferAsset,
        preservingExtensionFrom originalFileName: String
    ) throws -> String {
        let ext = URL(fileURLWithPath: originalFileName).pathExtension
        let normalizedExt = ext.isEmpty ? "jpg" : ext
        let newFileName = "\(UUID().uuidString).\(normalizedExt)"
        let url = localImageURL(for: newFileName)
        try asset.data.write(to: url, options: .atomic)
        if let image = UIImage(data: asset.data) {
            ImageCache.shared.store(image, for: newFileName)
        }
        return newFileName
    }

    static func localCanvasImageFileNamesOnDisk() -> Set<String> {
        let fileManager = FileManager.default
        let supportedExtensions = Set(["jpg", "jpeg", "png", "gif", "webp", "heic", "heif"])
        var fileNames = Set<String>()

        let candidateDirectories = [
            applicationSupportDirectory(),
            fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        ]

        for directoryURL in candidateDirectories {
            guard let candidateURLs = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in candidateURLs {
                let ext = url.pathExtension.lowercased()
                guard supportedExtensions.contains(ext) else { continue }
                guard isCanvasImageFileName(url.lastPathComponent) else { continue }
                fileNames.insert(url.lastPathComponent)
            }
        }

        return fileNames
    }

    static func runCanvasImageMaintenance(
        referencedFileNames: Set<String>,
        olderThan minimumAge: TimeInterval = 48 * 60 * 60
    ) throws {
        let fileManager = FileManager.default
        let now = Date()
        let imagesURL = applicationSupportDirectory()
        let legacyDocumentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]

        func maintain(directoryURL: URL, migrateReferencedFiles: Bool) throws {
            guard let enumerator = fileManager.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            for case let fileURL as URL in enumerator {
                let resourceValues = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard resourceValues.isRegularFile == true else { continue }

                let fileName = fileURL.lastPathComponent
                guard isCanvasImageFileName(fileName) else { continue }

                if referencedFileNames.contains(fileName) {
                    if migrateReferencedFiles, fileURL.deletingLastPathComponent() == legacyDocumentsURL {
                        let destinationURL = imagesURL.appendingPathComponent(fileName)
                        if !fileManager.fileExists(atPath: destinationURL.path) {
                            try? fileManager.moveItem(at: fileURL, to: destinationURL)
                        }
                    }
                    continue
                }

                let modifiedAt = resourceValues.contentModificationDate ?? .distantPast
                guard now.timeIntervalSince(modifiedAt) >= minimumAge else { continue }

                try? fileManager.removeItem(at: fileURL)
                ImageCache.shared.remove(for: fileName)
            }
        }

        try maintain(directoryURL: imagesURL, migrateReferencedFiles: false)
        try maintain(directoryURL: legacyDocumentsURL, migrateReferencedFiles: true)
    }
}
