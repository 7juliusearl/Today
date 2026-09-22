import Foundation
import CryptoKit

@main struct ReleaseTool {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let privateDir = root.appendingPathComponent(".today-release-signing")
        let privateURL = privateDir.appendingPathComponent("private-key")
        let publicURL = root.appendingPathComponent("update-public-key.txt")
        if args == ["init"] {
            guard !FileManager.default.fileExists(atPath: privateURL.path), !FileManager.default.fileExists(atPath: publicURL.path) else { throw TodayUpdateError("A release key already exists. Never replace it for existing installations.") }
            try FileManager.default.createDirectory(at: privateDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let key = Curve25519.Signing.PrivateKey()
            try key.rawRepresentation.write(to: privateURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateURL.path)
            try (key.publicKey.rawRepresentation.base64EncodedString() + "\n").write(to: publicURL, atomically: true, encoding: .utf8)
            print("Release key created. Back up .today-release-signing privately; never upload it.")
            return
        }
        guard args.count == 4, args[0] == "manifest" else { throw TodayUpdateError("Usage: release-tool init | manifest /path/Today.zip HTTPS_ZIP_LINK /path/release-notes.txt") }
        let zip = URL(fileURLWithPath: args[1])
        let url = try TodayUpdateFiles.downloadURL(args[2])
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: privateURL))
        guard try String(contentsOf: publicURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) == key.publicKey.rawRepresentation.base64EncodedString() else { throw TodayUpdateError("The private key does not match this app’s public key.") }
        // Read the actual archive metadata, not a possibly changed working-tree version.
        let raw = try TodayUpdateFiles.run("/usr/bin/unzip", ["-p", zip.path, "Today/.today-release.json"])
        let baseline = try JSONDecoder().decode(TodayBaseline.self, from: Data(raw.utf8))
        let archive = try Data(contentsOf: zip, options: .mappedIfSafe)
        guard archive.count <= TodayUpdateFiles.maxArchiveBytes else { throw TodayUpdateError("The ZIP is too large.") }
        let release = TodayRelease(version: baseline.version, build: baseline.build, notes: try String(contentsOfFile: args[3], encoding: .utf8), url: url.absoluteString, sha256: TodayUpdateFiles.hash(archive), bytes: archive.count)
        let payload = try JSONEncoder().encode(release)
        let envelope = SignedTodayRelease(payload: payload.base64EncodedString(), signature: try key.signature(for: payload).base64EncodedString())
        let output = zip.deletingLastPathComponent().appendingPathComponent("latest.json")
        try JSONEncoder().encode(envelope).write(to: output, options: .atomic)
        print("Publish \(output.path) by updating the existing latest.json file in Dropbox.")
    }
}
