import Foundation

/// Generates signed and unsigned Apple Encrypted DNS configuration profiles (`.mobileconfig`).
/// Supports removal passcode locking to prevent unauthorized profile deletion in iOS Settings.
public final class DnsProfileGenerator: @unchecked Sendable {
    public static let shared = DnsProfileGenerator()
    
    public struct ProfileConfig: Sendable {
        public let dohUrl: String
        public let profileName: String
        public let organization: String
        public let removalPasscode: String?
        public let profileUuid: String
        public let payloadUuid: String
        
        public init(
            dohUrl: String = "https://elevation-bufing-mel-shots.trycloudflare.com/dns-query",
            profileName: String = "FocusDNS Encrypted Protection",
            organization: String = "FocusDNS Security",
            removalPasscode: String? = nil,
            profileUuid: String = UUID().uuidString,
            payloadUuid: String = UUID().uuidString
        ) {
            self.dohUrl = dohUrl
            self.profileName = profileName
            self.organization = organization
            self.removalPasscode = removalPasscode
            self.profileUuid = profileUuid
            self.payloadUuid = payloadUuid
        }
    }
    
    public func generateMobileConfig(config: ProfileConfig = ProfileConfig()) -> String {
        var passcodeBlock = ""
        if let code = config.removalPasscode, !code.isEmpty {
            passcodeBlock = """
                <key>HasRemovalPasscode</key>
                <true/>
                <key>RemovalPassword</key>
                <string>\(code)</string>
            """
        }
        
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>PayloadContent</key>
            <array>
                <dict>
                    <key>DNSSettings</key>
                    <dict>
                        <key>DNSProtocol</key>
                        <string>HTTPS</string>
                        <key>ServerURL</key>
                        <string>\(config.dohUrl)</string>
                    </dict>
                    <key>PayloadDescription</key>
                    <string>Configures encrypted DNS-over-HTTPS filtering for FocusDNS.</string>
                    <key>PayloadDisplayName</key>
                    <string>\(config.profileName)</string>
                    <key>PayloadIdentifier</key>
                    <string>com.focusdns.dns.managed</string>
                    <key>PayloadType</key>
                    <string>com.apple.dnsSettings.managed</string>
                    <key>PayloadUUID</key>
                    <string>\(config.payloadUuid)</string>
                    <key>PayloadVersion</key>
                    <integer>1</integer>
                </dict>
            </array>
            <key>PayloadDescription</key>
            <string>FocusDNS on-device network protection and distraction blocking profile.</string>
            <key>PayloadDisplayName</key>
            <string>\(config.profileName)</string>
            <key>PayloadIdentifier</key>
            <string>com.focusdns.mobileconfig</string>
            <key>PayloadOrganization</key>
            <string>\(config.organization)</string>
            <key>PayloadRemovalDisallowed</key>
            <false/>
            <key>PayloadType</key>
            <string>Configuration</string>
            <key>PayloadUUID</key>
            <string>\(config.profileUuid)</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
        \(passcodeBlock)
        </dict>
        </plist>
        """
    }
}
