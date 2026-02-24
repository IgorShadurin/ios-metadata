import Foundation

public struct MetadataField: Equatable, Sendable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public struct MetadataSection: Equatable, Sendable {
    public let title: String
    public let icon: String
    public let fields: [MetadataField]

    public init(title: String, icon: String, fields: [MetadataField]) {
        self.title = title
        self.icon = icon
        self.fields = fields
    }
}

public struct MetadataSectionBuilder: Sendable {
    public private(set) var sections: [MetadataSection] = []

    public init() {}

    public mutating func appendSection(title: String, icon: String, fields: [MetadataField]) {
        guard !fields.isEmpty else { return }
        sections.append(MetadataSection(title: title, icon: icon, fields: fields))
    }

    public static func fields(from pairs: [(String, String?)]) -> [MetadataField] {
        pairs.compactMap { key, value in
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                return nil
            }
            return MetadataField(key: key, value: trimmed)
        }
    }
}

public enum MetadataFormatter {
    public static func fileSize(_ bytes: Int64?) -> String {
        guard let bytes, bytes >= 0 else { return "Unknown" }
        let byteFormatter = ByteCountFormatter()
        byteFormatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB, .useBytes]
        byteFormatter.countStyle = .file
        byteFormatter.includesUnit = true
        byteFormatter.isAdaptive = true
        return byteFormatter.string(fromByteCount: bytes)
    }

    public static func bitrate(_ bitsPerSecond: Double?) -> String {
        guard let bitsPerSecond, bitsPerSecond > 0 else { return "Unknown" }

        if bitsPerSecond >= 1_000_000_000 {
            return String(format: "%.2f Gbps", bitsPerSecond / 1_000_000_000)
        }

        if bitsPerSecond >= 1_000_000 {
            return String(format: "%.2f Mbps", bitsPerSecond / 1_000_000)
        }

        if bitsPerSecond >= 1_000 {
            return String(format: "%.2f Kbps", bitsPerSecond / 1_000)
        }

        return String(format: "%.0f bps", bitsPerSecond)
    }

    public static func duration(seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "Unknown" }
        let durationFormatter = DateComponentsFormatter()
        durationFormatter.unitsStyle = .abbreviated
        durationFormatter.allowedUnits = [.hour, .minute, .second]
        durationFormatter.zeroFormattingBehavior = [.dropLeading]
        return durationFormatter.string(from: seconds) ?? String(format: "%.2f s", seconds)
    }

    public static func coordinate(latitude: Double, longitude: Double) -> String {
        String(format: "%.6f, %.6f", latitude, longitude)
    }
}

public enum InspectionStep: String, Codable, Equatable, Sendable {
    case source
    case inspecting
    case result
}

public struct InspectionState: Codable, Equatable, Sendable {
    public var step: InspectionStep
    public var isRunning: Bool
    public var hasReport: Bool

    public init(step: InspectionStep = .source, isRunning: Bool = false, hasReport: Bool = false) {
        self.step = step
        self.isRunning = isRunning
        self.hasReport = hasReport
    }
}

public enum InspectionEvent: Equatable, Sendable {
    case started
    case baselineReady
    case enrichmentFinished
    case failed
    case cancelled
    case reset
}

public enum InspectionTransitionError: Error, LocalizedError, Equatable {
    case invalidTransition

    public var errorDescription: String? {
        switch self {
        case .invalidTransition:
            return "This action is not allowed in the current inspection state."
        }
    }
}

public struct InspectionWorkflowReducer {
    public init() {}

    public func transition(from state: InspectionState, event: InspectionEvent) throws -> InspectionState {
        switch event {
        case .started:
            guard !state.isRunning else { throw InspectionTransitionError.invalidTransition }
            return InspectionState(step: .inspecting, isRunning: true, hasReport: false)

        case .baselineReady:
            guard state.isRunning else { throw InspectionTransitionError.invalidTransition }
            return InspectionState(step: .inspecting, isRunning: true, hasReport: true)

        case .enrichmentFinished:
            guard state.isRunning, state.hasReport else { throw InspectionTransitionError.invalidTransition }
            return InspectionState(step: .result, isRunning: false, hasReport: true)

        case .failed, .cancelled:
            return InspectionState(step: state.hasReport ? .result : .source, isRunning: false, hasReport: state.hasReport)

        case .reset:
            return InspectionState(step: .source, isRunning: false, hasReport: false)
        }
    }
}
