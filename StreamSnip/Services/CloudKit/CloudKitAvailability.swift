//
//  CloudKitAvailability.swift
//  StreamSnip
//
//  Detects whether the app was signed with the iCloud container entitlement.
//

import Foundation
#if os(macOS)
import Security
#endif

/// Sideloaded installs (AltStore, SideStore, Sideloadly, …) are re-signed by a
/// team that cannot register `iCloud.com.alzimerahmed.StreamSnip` (container IDs are
/// globally unique), so the iCloud entitlements are stripped or remapped.
/// `CKContainer(identifier:)` fatally traps in that state, so the container
/// must never be created when the entitlement is missing.
enum CloudKitAvailability {
    /// Whether CloudKit APIs may be used in this installation.
    ///
    /// Determined by parsing the embedded provisioning profile. Builds without
    /// an embedded profile fall back to the running binary's actual code-signing
    /// entitlements on macOS (unsigned CI/sideload builds have none, and
    /// `CKContainer(identifier:)` traps there); on iOS a missing profile means
    /// App Store, TestFlight or simulator, which always carry the entitlement.
    static let isAvailable: Bool = {
        if let entitlements = embeddedProvisioningEntitlements() {
            let containers = entitlements["com.apple.developer.icloud-container-identifiers"] as? [String] ?? []
            return containers.contains(AppIdentifiers.iCloudContainer)
        }
        #if os(macOS)
        guard let containers = secTaskEntitlementContainers() else {
            return false
        }
        return containers.contains(AppIdentifiers.iCloudContainer)
        #else
        return true
        #endif
    }()

    #if os(macOS)
    /// The iCloud container identifiers the running binary is signed with, or
    /// nil when the entitlement is absent (unsigned builds).
    private static func secTaskEntitlementContainers() -> [String]? {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                  task,
                  "com.apple.developer.icloud-container-identifiers" as CFString,
                  nil
              )
        else { return nil }
        return (value as? [Any])?.compactMap { $0 as? String }
    }
    #endif

    /// Extracts the entitlements dictionary from the embedded provisioning
    /// profile — a CMS blob wrapping an XML property list.
    private static func embeddedProvisioningEntitlements() -> [String: Any]? {
        #if os(macOS)
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/embedded.provisionprofile")
        #else
        guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") else { return nil }
        let url = URL(fileURLWithPath: path)
        #endif

        guard let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data.subdata(in: start.lowerBound..<end.upperBound),
                  format: nil
              ),
              let profile = plist as? [String: Any]
        else { return nil }

        return profile["Entitlements"] as? [String: Any]
    }
}
