import Foundation
import PhotosUI
import UIKit

enum InputChannel: String {
    case files = "Files"
    case photos = "Photos"

    var icon: String {
        switch self {
        case .files:
            return "folder"
        case .photos:
            return "photo.on.rectangle"
        }
    }
}

struct MetadataReportSnapshot {
    var itemName: String
    var itemSubtitle: String
    var channel: InputChannel
    var sections: [MetadataSection]
    var warnings: [String]
    var previewImage: UIImage?
    var inspectedAt: Date
    var sourceURL: URL
}

struct MetadataInspectionRequest {
    var url: URL
    var channel: InputChannel
    var photoAssetIdentifier: String?
}

struct ShowcaseConfiguration {
    enum State: String {
        case source
        case inspecting
        case result
    }

    let state: State

    static func fromLaunchArguments() -> ShowcaseConfiguration? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--showcase-state"), index + 1 < arguments.count else {
            return nil
        }

        guard let state = State(rawValue: arguments[index + 1]) else {
            return nil
        }

        return ShowcaseConfiguration(state: state)
    }
}
