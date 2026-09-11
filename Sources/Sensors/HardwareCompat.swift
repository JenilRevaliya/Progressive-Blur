import Foundation
@preconcurrency import IOKit.hid

public enum HardwareSupportStatus: Equatable, Sendable {
    case supported(modelName: String)
    case unsupported(modelName: String, reason: String)
    case unknown(modelIdentifier: String)
    
    public var isSupported: Bool {
        if case .supported = self { return true }
        return false
    }
    
    public var summary: String {
        switch self {
        case .supported(let modelName):
            return "Supported hardware: \(modelName)"
        case .unsupported(let modelName, let reason):
            return "\(modelName): \(reason)"
        case .unknown(let modelIdentifier):
            return "Unknown hardware (\(modelIdentifier)). Probing HID subsystem..."
        }
    }
}

public enum SensorProbeResult: @unchecked Sendable {
    case foundStandard(device: IOHIDDevice)
    case foundVendorSpecific
    case notFound
}

public struct HardwareCompat {
    public let modelIdentifier: String
    
    public static var current: HardwareCompat {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [UInt8](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let identifier = String(decoding: model.prefix(while: { $0 != 0 }), as: UTF8.self)
        return HardwareCompat(modelIdentifier: identifier)
    }
    
    public var supportStatus: HardwareSupportStatus {
        if let friendlyName = Self.supportedModels[modelIdentifier] {
            return .supported(modelName: friendlyName)
        }
        if let reason = Self.unsupportedReason(for: modelIdentifier) {
            let friendly = Self.friendlyModelName(for: modelIdentifier)
            return .unsupported(modelName: friendly, reason: reason)
        }
        return .unknown(modelIdentifier: modelIdentifier)
    }
    
    public static func friendlyModelName(for id: String) -> String {
        if id == "MacBookAir10,1" {
            return "MacBook Air (M1, 2020)"
        }
        if let name = supportedModels[id] {
            return name
        }
        return id
    }
    
    public var hasHardwareNotch: Bool {
        // 14" and 16" MacBook Pro models (M1 Pro/Max 2021, M2 Pro/Max 2023, M3, M4)
        if modelIdentifier.hasPrefix("MacBookPro18,") || modelIdentifier.hasPrefix("Mac14,5") || modelIdentifier.hasPrefix("Mac14,6") || modelIdentifier.hasPrefix("Mac14,9") || modelIdentifier.hasPrefix("Mac14,10") || modelIdentifier.hasPrefix("Mac15,") || modelIdentifier.hasPrefix("Mac16,") {
            return true
        }
        // MacBook Air M2+ (2022+)
        let notchAirs: Set = ["Mac14,2", "Mac14,15", "Mac15,2", "Mac15,13", "Mac16,12", "Mac16,13"]
        if notchAirs.contains(modelIdentifier) {
            return true
        }
        return false
    }
    
    private static let supportedModels: [String: String] = [
        // MacBook Pro 16-inch 2019 (Intel)
        "MacBookPro16,1": "MacBook Pro (16-inch, 2019)",
        "MacBookPro16,4": "MacBook Pro (16-inch, 2019)",
        // MacBook Pro 14/16-inch 2021 (M1 Pro / Max)
        "MacBookPro18,3": "MacBook Pro (14-inch, 2021)",
        "MacBookPro18,4": "MacBook Pro (14-inch, 2021)",
        "MacBookPro18,1": "MacBook Pro (16-inch, 2021)",
        "MacBookPro18,2": "MacBook Pro (16-inch, 2021)",
        // MacBook Pro 14/16-inch 2023 (M2 Pro / Max)
        "Mac14,9": "MacBook Pro (14-inch, M2 Pro, 2023)",
        "Mac14,5": "MacBook Pro (14-inch, M2 Max, 2023)",
        "Mac14,10": "MacBook Pro (16-inch, M2 Pro, 2023)",
        "Mac14,6": "MacBook Pro (16-inch, M2 Max, 2023)",
        // MacBook Pro 14/16-inch late 2023 (M3 / Pro / Max)
        "Mac15,3": "MacBook Pro (14-inch, M3, 2023)",
        "Mac15,6": "MacBook Pro (14-inch, M3 Pro, 2023)",
        "Mac15,8": "MacBook Pro (14-inch, M3 Max, 2023)",
        "Mac15,7": "MacBook Pro (16-inch, M3 Pro, 2023)",
        "Mac15,9": "MacBook Pro (16-inch, M3 Max, 2023)",
        "Mac15,11": "MacBook Pro (16-inch, M3 Max, 2023)",
        // MacBook Pro 2024 (M4 / Pro / Max)
        "Mac16,1": "MacBook Pro (14-inch, M4, 2024)",
        "Mac16,6": "MacBook Pro (14-inch, M4 Pro, 2024)",
        "Mac16,8": "MacBook Pro (14-inch, M4 Max, 2024)",
        "Mac16,5": "MacBook Pro (16-inch, M4 Pro, 2024)",
        "Mac16,7": "MacBook Pro (16-inch, M4 Pro, 2024)",
        "Mac16,9": "MacBook Pro (16-inch, M4 Max, 2024)",
        "Mac16,10": "MacBook Pro (16-inch, M4 Max, 2024)",
        // MacBook Air M2+ (2022+)
        "Mac14,2": "MacBook Air (13-inch, M2, 2022)",
        "Mac14,15": "MacBook Air (15-inch, M2, 2023)",
        "Mac15,2": "MacBook Air (13-inch, M3, 2024)",
        "Mac15,13": "MacBook Air (15-inch, M3, 2024)",
        "Mac16,12": "MacBook Air (13-inch, M4, 2025)",
        "Mac16,13": "MacBook Air (15-inch, M4, 2025)"
    ]
    
    private static func unsupportedReason(for id: String) -> String? {
        if id == "MacBookAir10,1" {
            return "MacBook Air (M1, 2020) uses a binary magnetic lid switch instead of Apple's angular lid angle sensor (0x8104). The app operates in Simulated / Diagnostic Mode."
        }
        if id.hasPrefix("MacBookAir") {
            return "Pre-M2 MacBook Air models lack the continuous lid angle sensor. Using Simulated Mode."
        }
        if id.hasPrefix("Macmini") || id.hasPrefix("MacPro") || id.hasPrefix("iMac") || id.hasPrefix("Mac13,") || id.hasPrefix("Mac14,13") || id.hasPrefix("Mac14,14") {
            return "Desktop Macs do not have a physical clamshell lid. Using Simulated Mode."
        }
        let mbp13 = ["MacBookPro17,1", "Mac14,7", "MacBookPro15,2", "MacBookPro15,4", "MacBookPro16,2", "MacBookPro16,3"]
        if mbp13.contains(id) {
            return "13-inch MacBook Pro models do not feature the lid angle sensor. Using Simulated Mode."
        }
        return nil
    }
}
