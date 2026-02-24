import AVFoundation
import CoreLocation
import CoreMedia
import Foundation
import ImageIO
import PDFKit
import Photos
import UIKit
import UniformTypeIdentifiers

enum MetadataInspectorError: LocalizedError {
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "Could not access the selected file."
        }
    }
}

struct MetadataInspector {
    private let baselineKeys: Set<URLResourceKey> = [
        .nameKey,
        .typeIdentifierKey,
        .fileSizeKey,
        .fileAllocatedSizeKey,
        .creationDateKey,
        .contentModificationDateKey,
        .isRegularFileKey,
        .isDirectoryKey,
        .isReadableKey,
        .isWritableKey,
        .isUbiquitousItemKey,
        .ubiquitousItemDownloadingStatusKey
    ]

    func buildBaselineReport(for request: MetadataInspectionRequest) throws -> MetadataReportSnapshot {
        let resourceValues = try request.url.resourceValues(forKeys: baselineKeys)
        guard resourceValues.isRegularFile != false else {
            throw MetadataInspectorError.unreadableFile
        }

        let itemName = resourceValues.name ?? request.url.lastPathComponent
        let typeIdentifier = inferredTypeIdentifier(resourceValues: resourceValues, url: request.url)
        let utType = typeIdentifier.flatMap { UTType($0) } ?? UTType(filenameExtension: request.url.pathExtension)
        let channelLocation = request.channel == .photos ? "Photo Library" : request.url.deletingLastPathComponent().path

        let fileSize = resourceValues.fileSize ?? resourceValues.fileAllocatedSize
        let sizeText = MetadataFormatter.fileSize(fileSize.map(Int64.init))

        var builder = MetadataSectionBuilder()
        builder.appendSection(
            title: "General",
            icon: "doc.text.magnifyingglass",
            fields: MetadataSectionBuilder.fields(from: [
                ("Name", itemName),
                ("Location", channelLocation),
                ("Channel", request.channel.rawValue),
                ("File Size", sizeText),
                ("Created", string(from: resourceValues.creationDate)),
                ("Modified", string(from: resourceValues.contentModificationDate))
            ])
        )

        builder.appendSection(
            title: "Type",
            icon: "tag",
            fields: MetadataSectionBuilder.fields(from: [
                ("UTType Identifier", typeIdentifier),
                ("Preferred Extension", utType?.preferredFilenameExtension),
                ("MIME Type", utType?.preferredMIMEType),
                ("Category", categoryList(for: utType)),
                ("Readable", boolString(resourceValues.isReadable)),
                ("Writable", boolString(resourceValues.isWritable)),
                ("iCloud Item", boolString(resourceValues.isUbiquitousItem)),
                ("iCloud Status", resourceValues.ubiquitousItemDownloadingStatus?.rawValue)
            ])
        )

        let subtitle = [
            sizeText,
            request.channel.rawValue,
            utType?.localizedDescription ?? "Unknown type"
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " • ")

        return MetadataReportSnapshot(
            itemName: itemName,
            itemSubtitle: subtitle,
            channel: request.channel,
            sections: builder.sections,
            warnings: [],
            previewImage: nil,
            inspectedAt: Date(),
            sourceURL: request.url
        )
    }

    func enrich(
        report: MetadataReportSnapshot,
        request: MetadataInspectionRequest,
        includeRawMetadata: Bool
    ) async throws -> MetadataReportSnapshot {
        try Task.checkCancellation()

        let resourceValues = try request.url.resourceValues(forKeys: baselineKeys)
        let typeIdentifier = inferredTypeIdentifier(resourceValues: resourceValues, url: request.url)
        let utType = typeIdentifier.flatMap { UTType($0) } ?? UTType(filenameExtension: request.url.pathExtension)

        var nextReport = report
        var builder = MetadataSectionBuilder()
        for section in report.sections {
            builder.appendSection(title: section.title, icon: section.icon, fields: section.fields)
        }

        var warnings: [String] = []

        try Task.checkCancellation()
        let mediaSections = try await mediaSectionsIfAvailable(url: request.url, includeRawMetadata: includeRawMetadata)
        for section in mediaSections {
            builder.appendSection(title: section.title, icon: section.icon, fields: section.fields)
        }

        try Task.checkCancellation()
        let imageSections = imageSectionsIfAvailable(url: request.url, includeRawMetadata: includeRawMetadata)
        for section in imageSections.sections {
            builder.appendSection(title: section.title, icon: section.icon, fields: section.fields)
        }
        warnings.append(contentsOf: imageSections.warnings)

        try Task.checkCancellation()
        let pdfSections = pdfSectionsIfAvailable(url: request.url, utType: utType)
        for section in pdfSections {
            builder.appendSection(title: section.title, icon: section.icon, fields: section.fields)
        }

        try Task.checkCancellation()
        if let locationSection = photoLocationSection(assetIdentifier: request.photoAssetIdentifier) {
            builder.appendSection(title: locationSection.title, icon: locationSection.icon, fields: locationSection.fields)
        }

        nextReport.sections = builder.sections
        nextReport.warnings.append(contentsOf: warnings)
        nextReport.inspectedAt = Date()
        nextReport.previewImage = await previewImageForURL(url: request.url, utType: utType)
        return nextReport
    }

    private func mediaSectionsIfAvailable(url: URL, includeRawMetadata: Bool) async throws -> [MetadataSection] {
        let asset = AVURLAsset(url: url)

        guard let duration = try? await asset.load(.duration) else {
            return []
        }

        let tracks = (try? await asset.load(.tracks)) ?? []
        guard !tracks.isEmpty || duration.isNumeric else {
            return []
        }

        let isPlayable = (try? await asset.load(.isPlayable)) ?? false
        let hasProtectedContent = (try? await asset.load(.hasProtectedContent)) ?? false

        var totalBitrate: Double = 0
        var codecSet = Set<String>()
        var videoSummaries: [String] = []
        var audioSummaries: [String] = []

        for (index, track) in tracks.enumerated() {
            try Task.checkCancellation()
            let mediaType = track.mediaType
            let estimatedDataRate = Double((try? await track.load(.estimatedDataRate)) ?? 0)
            totalBitrate += max(estimatedDataRate, 0)

            let descriptions = (try? await track.load(.formatDescriptions)) ?? []
            let codecs = descriptions.compactMap(codecIdentifier(from:))
            for codec in codecs {
                codecSet.insert(codec)
            }

            if mediaType == .video {
                let size = (try? await track.load(.naturalSize)) ?? .zero
                let frameRate = Double((try? await track.load(.nominalFrameRate)) ?? 0)
                let codec = codecs.first ?? "unknown"
                let summary = "#\(index + 1): \(Int(abs(size.width)))x\(Int(abs(size.height))) • \(String(format: "%.2f", frameRate)) fps • \(MetadataFormatter.bitrate(estimatedDataRate)) • \(codec)"
                videoSummaries.append(summary)
            } else if mediaType == .audio {
                let codec = codecs.first ?? "unknown"
                let channelCount = descriptions
                    .compactMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame }
                    .first
                let sampleRate = descriptions
                    .compactMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mSampleRate }
                    .first

                var pieces = ["#\(index + 1)", MetadataFormatter.bitrate(estimatedDataRate), codec]
                if let channelCount {
                    pieces.append("\(channelCount) ch")
                }
                if let sampleRate {
                    pieces.append("\(Int(sampleRate)) Hz")
                }
                audioSummaries.append(pieces.joined(separator: " • "))
            }
        }

        var builder = MetadataSectionBuilder()
        builder.appendSection(
            title: "Media",
            icon: "film",
            fields: MetadataSectionBuilder.fields(from: [
                ("Duration", MetadataFormatter.duration(seconds: duration.seconds.isFinite ? duration.seconds : nil)),
                ("Playable", boolString(isPlayable)),
                ("Protected", boolString(hasProtectedContent)),
                ("Track Count", "\(tracks.count)"),
                ("Estimated Total Bitrate", MetadataFormatter.bitrate(totalBitrate > 0 ? totalBitrate : nil)),
                ("Codecs", codecSet.isEmpty ? nil : codecSet.sorted().joined(separator: ", "))
            ])
        )

        builder.appendSection(
            title: "Video Tracks",
            icon: "video",
            fields: videoSummaries.enumerated().map { index, value in
                MetadataField(key: "Track \(index + 1)", value: value)
            }
        )

        builder.appendSection(
            title: "Audio Tracks",
            icon: "waveform",
            fields: audioSummaries.enumerated().map { index, value in
                MetadataField(key: "Track \(index + 1)", value: value)
            }
        )

        if includeRawMetadata {
            let commonMetadata = (try? await asset.load(.commonMetadata)) ?? []
            if !commonMetadata.isEmpty {
                let flattened = commonMetadata.prefix(20).map { item in
                    let key = item.commonKey?.rawValue ?? item.identifier?.rawValue ?? "meta"
                    return MetadataField(key: key, value: item.identifier?.rawValue ?? "metadata item")
                }
                builder.appendSection(title: "Raw Media Metadata", icon: "list.bullet.rectangle", fields: flattened)
            }
        }

        return builder.sections
    }

    private func imageSectionsIfAvailable(url: URL, includeRawMetadata: Bool) -> (sections: [MetadataSection], warnings: [String]) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return ([], [])
        }

        var warnings: [String] = []
        var builder = MetadataSectionBuilder()

        let width = properties[kCGImagePropertyPixelWidth] as? Int
        let height = properties[kCGImagePropertyPixelHeight] as? Int
        let colorModel = properties[kCGImagePropertyColorModel] as? String
        let profileName = properties[kCGImagePropertyProfileName] as? String

        builder.appendSection(
            title: "Image",
            icon: "photo",
            fields: MetadataSectionBuilder.fields(from: [
                ("Dimensions", width != nil && height != nil ? "\(width!) x \(height!)" : nil),
                ("Color Model", colorModel),
                ("Profile", profileName),
                ("Frame Count", "\(CGImageSourceGetCount(source))")
            ])
        )

        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            let cameraMake = (properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] as? String
            let cameraModel = (properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] as? String
            let iso = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int]
            let exposure = exif[kCGImagePropertyExifExposureTime] as? Double

            builder.appendSection(
                title: "Capture",
                icon: "camera",
                fields: MetadataSectionBuilder.fields(from: [
                    ("Camera Make", cameraMake),
                    ("Camera Model", cameraModel),
                    ("ISO", iso?.first.map(String.init)),
                    ("Exposure", exposure.map { String(format: "%.5f s", $0) })
                ])
            )
        }

        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            let latitude = signedCoordinate(value: gps[kCGImagePropertyGPSLatitude] as? Double, ref: gps[kCGImagePropertyGPSLatitudeRef] as? String)
            let longitude = signedCoordinate(value: gps[kCGImagePropertyGPSLongitude] as? Double, ref: gps[kCGImagePropertyGPSLongitudeRef] as? String)
            let altitude = gps[kCGImagePropertyGPSAltitude] as? Double

            builder.appendSection(
                title: "Location",
                icon: "location",
                fields: MetadataSectionBuilder.fields(from: [
                    ("Coordinates", latitude != nil && longitude != nil ? MetadataFormatter.coordinate(latitude: latitude!, longitude: longitude!) : nil),
                    ("Altitude", altitude.map { String(format: "%.2f m", $0) })
                ])
            )
        } else {
            warnings.append("No embedded GPS metadata found in image.")
        }

        if includeRawMetadata {
            let rawText = prettyJSON(properties: properties)
            builder.appendSection(
                title: "Raw Image Metadata",
                icon: "text.alignleft",
                fields: MetadataSectionBuilder.fields(from: [
                    ("Payload", rawText)
                ])
            )
        }

        return (builder.sections, warnings)
    }

    private func pdfSectionsIfAvailable(url: URL, utType: UTType?) -> [MetadataSection] {
        guard (utType?.conforms(to: .pdf) ?? false), let document = PDFDocument(url: url) else {
            return []
        }

        let attributes = document.documentAttributes ?? [:]
        var builder = MetadataSectionBuilder()

        builder.appendSection(
            title: "PDF",
            icon: "doc.richtext",
            fields: MetadataSectionBuilder.fields(from: [
                ("Page Count", "\(document.pageCount)"),
                ("Title", attributes[PDFDocumentAttribute.titleAttribute] as? String),
                ("Author", attributes[PDFDocumentAttribute.authorAttribute] as? String),
                ("Subject", attributes[PDFDocumentAttribute.subjectAttribute] as? String),
                ("Creator", attributes[PDFDocumentAttribute.creatorAttribute] as? String),
                ("Producer", attributes[PDFDocumentAttribute.producerAttribute] as? String)
            ])
        )

        return builder.sections
    }

    private func photoLocationSection(assetIdentifier: String?) -> MetadataSection? {
        guard let assetIdentifier else { return nil }

        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = result.firstObject else { return nil }

        let coordinate = asset.location?.coordinate
        let locationString = coordinate.map {
            MetadataFormatter.coordinate(latitude: $0.latitude, longitude: $0.longitude)
        }

        let fields = MetadataSectionBuilder.fields(from: [
            ("Asset Identifier", asset.localIdentifier),
            ("Created", string(from: asset.creationDate)),
            ("Location", locationString)
        ])

        guard !fields.isEmpty else { return nil }
        return MetadataSection(title: "Photos Asset", icon: "photo.stack", fields: fields)
    }

    private func previewImageForURL(url: URL, utType: UTType?) async -> UIImage? {
        if utType?.conforms(to: .image) == true {
            return UIImage(contentsOfFile: url.path)
        }

        if utType?.conforms(to: .pdf) == true,
           let document = PDFDocument(url: url),
           let page = document.page(at: 0) {
            let bounds = page.bounds(for: .mediaBox)
            let target = CGSize(width: 640, height: max(320, 640 * bounds.height / max(1, bounds.width)))
            return page.thumbnail(of: target, for: .mediaBox)
        }

        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.load(.tracks), !tracks.isEmpty else {
            return nil
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 900, height: 900)

        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let imageRef = try? await generator.image(at: time).image else {
            return nil
        }

        return UIImage(cgImage: imageRef)
    }

    private func inferredTypeIdentifier(resourceValues: URLResourceValues, url: URL) -> String? {
        if let typeIdentifier = resourceValues.typeIdentifier {
            return typeIdentifier
        }

        let ext = url.pathExtension
        guard !ext.isEmpty else { return nil }
        return UTType(filenameExtension: ext)?.identifier
    }

    private func categoryList(for type: UTType?) -> String {
        guard let type else { return "Unknown" }

        var categories: [String] = []
        let mappings: [(UTType, String)] = [
            (.audiovisualContent, "Audiovisual"),
            (.movie, "Video"),
            (.audio, "Audio"),
            (.image, "Image"),
            (.pdf, "PDF"),
            (.text, "Text"),
            (.archive, "Archive"),
            (.sourceCode, "Source Code"),
            (.json, "JSON"),
            (.xml, "XML"),
            (.content, "Content")
        ]

        for (candidate, label) in mappings where type.conforms(to: candidate) {
            categories.append(label)
        }

        if categories.isEmpty {
            categories.append("General")
        }

        return Array(Set(categories)).sorted().joined(separator: ", ")
    }

    private func codecIdentifier(from formatDescription: CMFormatDescription) -> String? {
        let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDescription)
        guard mediaSubType != 0 else {
            return nil
        }

        let raw = fourCharacterCode(mediaSubType)
        return raw
    }

    private func fourCharacterCode(_ value: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]

        let isPrintableASCII = bytes.allSatisfy { $0 >= 32 && $0 <= 126 }
        if isPrintableASCII {
            return String(bytes: bytes, encoding: .ascii) ?? String(format: "0x%08X", value)
        }

        return String(format: "0x%08X", value)
    }

    private func signedCoordinate(value: Double?, ref: String?) -> Double? {
        guard var value else { return nil }

        if let ref {
            let normalized = ref.uppercased()
            if normalized == "S" || normalized == "W" {
                value *= -1
            }
        }

        return value
    }

    private func prettyJSON(properties: [CFString: Any]) -> String {
        let dictionary = properties.reduce(into: [String: String]()) { partialResult, entry in
            partialResult[entry.key as String] = "\(entry.value)"
        }

        guard let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted]),
              let json = String(data: data, encoding: .utf8)
        else {
            return "Unavailable"
        }

        if json.count <= 3_000 {
            return json
        }

        let endIndex = json.index(json.startIndex, offsetBy: 3_000)
        return String(json[..<endIndex]) + "…"
    }

    private func string(from date: Date?) -> String? {
        guard let date else { return nil }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func boolString(_ value: Bool?) -> String? {
        guard let value else { return nil }
        return value ? "Yes" : "No"
    }
}
