import Foundation
import Security

// Credentials travel over stdin/stdout pipes, never command-line arguments.
@main struct AsanaTrialKeychain {
    static func main() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.today-dashboard.asana-developer-trial",
            kSecAttrAccount as String: "developer"]
        let action = CommandLine.arguments.dropFirst().first ?? ""
        var status: OSStatus = errSecParam
        switch action {
        case "save":
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard !data.isEmpty else { exit(2) }
            status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var item = query
                item[kSecValueData as String] = data
                item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                status = SecItemAdd(item as CFDictionary, nil)
            }
        case "load":
            var request = query
            request[kSecReturnData as String] = true
            request[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            status = SecItemCopyMatching(request as CFDictionary, &result)
            if status == errSecSuccess, let data = result as? Data { FileHandle.standardOutput.write(data) }
        case "delete":
            status = SecItemDelete(query as CFDictionary)
            if status == errSecItemNotFound { status = errSecSuccess }
        default: break
        }
        guard status == errSecSuccess else {
            FileHandle.standardError.write(Data("Keychain operation failed (\(status)).\n".utf8))
            exit(1)
        }
    }
}
