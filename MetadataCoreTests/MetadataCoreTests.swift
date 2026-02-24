import Foundation
import Testing
@testable import MetadataCore

struct MetadataCoreTests {
    private let reducer = InspectionWorkflowReducer()

    @Test
    func fieldsBuilderDropsEmptyValues() {
        let fields = MetadataSectionBuilder.fields(from: [
            ("Name", " Report.pdf "),
            ("Codec", nil),
            ("Bitrate", ""),
            ("Location", "   "),
            ("Type", "public.pdf")
        ])

        #expect(fields == [
            MetadataField(key: "Name", value: "Report.pdf"),
            MetadataField(key: "Type", value: "public.pdf")
        ])
    }

    @Test
    func appendSectionSkipsEmptyFieldLists() {
        var builder = MetadataSectionBuilder()
        builder.appendSection(title: "General", icon: "doc", fields: [])
        builder.appendSection(title: "General", icon: "doc", fields: [MetadataField(key: "Name", value: "clip.mov")])

        #expect(builder.sections.count == 1)
        #expect(builder.sections.first?.title == "General")
    }

    @Test
    func formatterHandlesFileSizeAndBitrateEdges() {
        #expect(MetadataFormatter.fileSize(nil) == "Unknown")
        #expect(MetadataFormatter.fileSize(-1) == "Unknown")
        #expect(MetadataFormatter.fileSize(0).contains("bytes"))

        #expect(MetadataFormatter.bitrate(nil) == "Unknown")
        #expect(MetadataFormatter.bitrate(0) == "Unknown")
        #expect(MetadataFormatter.bitrate(640_000).contains("Kbps"))
        #expect(MetadataFormatter.bitrate(12_500_000).contains("Mbps"))
    }

    @Test
    func formatterProducesCoordinateAndDuration() {
        let point = MetadataFormatter.coordinate(latitude: 40.712776, longitude: -74.005974)
        #expect(point.contains("40.712"))
        #expect(point.contains("-74.005"))

        #expect(MetadataFormatter.duration(seconds: nil) == "Unknown")
        #expect(MetadataFormatter.duration(seconds: 0) == "Unknown")
        #expect(MetadataFormatter.duration(seconds: 75).contains("1m"))
    }

    @Test
    func workflowHappyPath() throws {
        var state = InspectionState()

        state = try reducer.transition(from: state, event: .started)
        #expect(state.step == .inspecting)
        #expect(state.isRunning)
        #expect(!state.hasReport)

        state = try reducer.transition(from: state, event: .baselineReady)
        #expect(state.step == .inspecting)
        #expect(state.hasReport)

        state = try reducer.transition(from: state, event: .enrichmentFinished)
        #expect(state.step == .result)
        #expect(!state.isRunning)
        #expect(state.hasReport)

        state = try reducer.transition(from: state, event: .reset)
        #expect(state == InspectionState())
    }

    @Test
    func workflowRejectsInvalidTransitions() {
        #expect(throws: InspectionTransitionError.invalidTransition) {
            _ = try reducer.transition(from: InspectionState(), event: .baselineReady)
        }

        #expect(throws: InspectionTransitionError.invalidTransition) {
            _ = try reducer.transition(from: InspectionState(), event: .enrichmentFinished)
        }

        #expect(throws: InspectionTransitionError.invalidTransition) {
            _ = try reducer.transition(from: InspectionState(step: .inspecting, isRunning: true, hasReport: false), event: .started)
        }
    }

    @Test
    func workflowCancelAndFailBehaviors() throws {
        let running = InspectionState(step: .inspecting, isRunning: true, hasReport: true)
        let cancelled = try reducer.transition(from: running, event: .cancelled)
        #expect(cancelled.step == .result)
        #expect(!cancelled.isRunning)

        let failedNoResult = try reducer.transition(from: InspectionState(step: .inspecting, isRunning: true, hasReport: false), event: .failed)
        #expect(failedNoResult.step == .source)
        #expect(!failedNoResult.hasReport)
    }
}
