import Foundation
import IOKit
import SystemConfiguration

/// The host's identity, read without any privacy-sensitive identifier: no MAC address, no serial number.
enum MachineIdentity {
    /// The hardware UUID of this machine (`IOPlatformUUID`).
    ///
    /// - Returns: The UUID string, or nil when the registry entry cannot be read.
    static func hardwareUuid() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let property = IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)
        return property?.takeRetainedValue() as? String
    }

    /// The user-visible computer name.
    ///
    /// - Returns: The name from System Settings, or the host name when it is unset.
    static func computerName() -> String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? ProcessInfo.processInfo.hostName
    }

    /// The short code for a machine, in the instance-code convention.
    ///
    /// - Parameter hardwareUuid: The machine's hardware UUID.
    /// - Returns: A code of the form `machine_<4 hex>`.
    static func code(for hardwareUuid: String) -> String {
        InstanceIdentity.code(repoName: "machine", absolutePath: hardwareUuid)
    }
}
