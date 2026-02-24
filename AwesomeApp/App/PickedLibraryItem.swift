import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct PickedLibraryItem: Transferable {
    let localURL: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .item) { incoming in
            let destinationURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(incoming.file.pathExtension)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try FileManager.default.copyItem(at: incoming.file, to: destinationURL)
            return PickedLibraryItem(localURL: destinationURL)
        }
    }
}
