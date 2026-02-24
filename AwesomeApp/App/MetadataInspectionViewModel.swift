import Combine
import Foundation
import PhotosUI
import SwiftUI
import UIKit

@MainActor
final class MetadataInspectionViewModel: ObservableObject {
    @Published var pickerItem: PhotosPickerItem?

    @Published private(set) var state = InspectionState()
    @Published private(set) var report: MetadataReportSnapshot?
    @Published private(set) var statusMessage = "Pick any item from Photos or Files to inspect metadata."
    @Published private(set) var errorMessage: String?
    @Published private(set) var isCancelling = false

    @AppStorage("metadata.includeRawMetadata") var includeRawMetadata = false {
        didSet {
            guard includeRawMetadata != oldValue, report != nil, activeRequest != nil else { return }
            rerunInspectionForCurrentItem(reason: "Updating raw metadata visibility...")
        }
    }

    @AppStorage("metadata.showOnlyEssential") var showOnlyEssential = false

    private let inspector = MetadataInspector()
    private let reducer = InspectionWorkflowReducer()
    private var inspectionTask: Task<Void, Never>?
    private var activeRequest: MetadataInspectionRequest?

    var isInspecting: Bool {
        state.isRunning
    }

    var canCancel: Bool {
        state.isRunning && !isCancelling
    }

    var stepTitle: String {
        switch state.step {
        case .source:
            return "Source"
        case .inspecting:
            return "Inspecting"
        case .result:
            return "Result"
        }
    }

    init() {
        applyShowcaseStateIfNeeded()
    }

    func handlePickerChange() async {
        guard let pickerItem else { return }

        errorMessage = nil
        statusMessage = "Loading item from Photos..."

        do {
            guard let picked = try await pickerItem.loadTransferable(type: PickedLibraryItem.self) else {
                throw MetadataInspectorError.unreadableFile
            }

            let request = MetadataInspectionRequest(
                url: picked.localURL,
                channel: .photos,
                photoAssetIdentifier: pickerItem.itemIdentifier
            )
            beginInspection(request: request)
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Failed to load item from Photos."
        }
    }

    func handleImportedFile(url: URL) async {
        errorMessage = nil
        statusMessage = "Loading item from Files..."

        do {
            let localURL = try copyToTemporaryLocation(url: url)
            let request = MetadataInspectionRequest(url: localURL, channel: .files, photoAssetIdentifier: nil)
            beginInspection(request: request)
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Failed to load imported file."
        }
    }

    func handleImportFailure(_ errorDescription: String) {
        errorMessage = "File import failed: \(errorDescription)"
    }

    func cancelInspection() {
        guard canCancel else { return }
        isCancelling = true
        inspectionTask?.cancel()
    }

    func reset() {
        inspectionTask?.cancel()
        inspectionTask = nil
        activeRequest = nil
        report = nil
        errorMessage = nil
        statusMessage = "Pick any item from Photos or Files to inspect metadata."
        isCancelling = false

        do {
            state = try reducer.transition(from: state, event: .reset)
        } catch {
            state = InspectionState()
        }
    }

    private func rerunInspectionForCurrentItem(reason: String) {
        guard let request = activeRequest else { return }
        statusMessage = reason
        beginInspection(request: request)
    }

    private func beginInspection(request: MetadataInspectionRequest) {
        inspectionTask?.cancel()
        inspectionTask = nil
        activeRequest = request

        inspectionTask = Task { [weak self] in
            guard let self else { return }

            do {
                self.state = try self.reducer.transition(from: self.state, event: .started)
                self.errorMessage = nil
                self.isCancelling = false
                self.statusMessage = "Reading baseline metadata..."

                let baselineReport = try self.inspector.buildBaselineReport(for: request)
                self.report = baselineReport
                self.state = try self.reducer.transition(from: self.state, event: .baselineReady)
                self.statusMessage = "Extracting deep technical metadata..."

                let enriched = try await self.inspector.enrich(
                    report: baselineReport,
                    request: request,
                    includeRawMetadata: self.includeRawMetadata
                )

                try Task.checkCancellation()
                self.report = enriched
                self.state = try self.reducer.transition(from: self.state, event: .enrichmentFinished)
                self.statusMessage = "Metadata inspection complete."
            } catch is CancellationError {
                self.statusMessage = "Metadata inspection cancelled."
                self.errorMessage = nil
                do {
                    self.state = try self.reducer.transition(from: self.state, event: .cancelled)
                } catch {
                    self.state = InspectionState(step: self.report == nil ? .source : .result, isRunning: false, hasReport: self.report != nil)
                }
            } catch {
                self.statusMessage = "Metadata inspection failed."
                self.errorMessage = error.localizedDescription
                do {
                    self.state = try self.reducer.transition(from: self.state, event: .failed)
                } catch {
                    self.state = InspectionState(step: self.report == nil ? .source : .result, isRunning: false, hasReport: self.report != nil)
                }
            }

            self.isCancelling = false
            self.inspectionTask = nil
        }
    }

    private func copyToTemporaryLocation(url: URL) throws -> URL {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.copyItem(at: url, to: destinationURL)
        return destinationURL
    }

    private func applyShowcaseStateIfNeeded() {
        guard let showcase = ShowcaseConfiguration.fromLaunchArguments() else { return }

        let sampleURL = FileManager.default.temporaryDirectory.appendingPathComponent("sample.mov")
        let sections = [
            MetadataSection(
                title: "General",
                icon: "doc.text.magnifyingglass",
                fields: [
                    MetadataField(key: "Name", value: "SampleClip.mov"),
                    MetadataField(key: "Location", value: "Photo Library"),
                    MetadataField(key: "File Size", value: "238 MB")
                ]
            ),
            MetadataSection(
                title: "Media",
                icon: "film",
                fields: [
                    MetadataField(key: "Duration", value: "48s"),
                    MetadataField(key: "Codecs", value: "hvc1, aac "),
                    MetadataField(key: "Estimated Total Bitrate", value: "42.70 Mbps")
                ]
            )
        ]

        let demoImage = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 360)).image { context in
            UIColor.systemCyan.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
            UIColor.systemBlue.withAlphaComponent(0.35).setFill()
            context.fill(CGRect(x: 0, y: 210, width: 640, height: 150))
        }

        report = MetadataReportSnapshot(
            itemName: "SampleClip.mov",
            itemSubtitle: "238 MB • Photos • QuickTime Movie",
            channel: .photos,
            sections: showcase.state == .source ? [] : sections,
            warnings: showcase.state == .result ? [] : ["No embedded GPS metadata found in image."],
            previewImage: showcase.state == .source ? nil : demoImage,
            inspectedAt: Date(),
            sourceURL: sampleURL
        )

        switch showcase.state {
        case .source:
            state = InspectionState(step: .source, isRunning: false, hasReport: false)
            report = nil
            statusMessage = "Pick any item from Photos or Files to inspect metadata."
        case .inspecting:
            state = InspectionState(step: .inspecting, isRunning: true, hasReport: true)
            statusMessage = "Extracting deep technical metadata..."
        case .result:
            state = InspectionState(step: .result, isRunning: false, hasReport: true)
            statusMessage = "Metadata inspection complete."
        }
    }
}
