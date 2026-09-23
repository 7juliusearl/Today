import AppKit
import SwiftUI
import Network
import SystemConfiguration
import CoreImage.CIFilterBuiltins

// Deliberately opt-in, read-only LAN service. No filesystem URLs or remote commands.
@MainActor final class CompanionServer: ObservableObject {
    @Published var running = false
    @Published var starting = false
    @Published var status = "Sharing is off."
    @Published var links: [String] = []
    var snapshot = ""
    private var listener: NWListener?
    private var addressRefresh: Timer?
    private var connections: [UUID: NWConnection] = [:]
    private var token = ""
    private var assets: [String: Data] = [:]
    private var html = Data()
    private let port: UInt16 = 8787
    private let dashboardRoot: URL?
    private let resourceRoot: URL?
    private let pairingFile: URL
    private let preferences: UserDefaults
    @Published var resumeOnLaunch: Bool {
        didSet { preferences.set(resumeOnLaunch, forKey: "companionResumeOnLaunch") }
    }
    init(dashboardRoot: URL? = nil, resourceRoot: URL? = nil, pairingFile: URL? = nil, preferences: UserDefaults = .standard) {
        self.dashboardRoot = dashboardRoot; self.resourceRoot = resourceRoot
        self.preferences = preferences
        self.resumeOnLaunch = preferences.bool(forKey: "companionResumeOnLaunch")
        self.pairingFile = pairingFile ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.today-dashboard.calendar-prototype")
            .appendingPathComponent("companion-pairing")
    }
    private func pairingToken() throws -> String {
        if FileManager.default.fileExists(atPath: pairingFile.path) {
            let saved = try String(contentsOf: pairingFile, encoding: .utf8)
            guard saved.count == 72, saved.allSatisfy({ $0.isHexDigit || $0 == "-" }) else {
                throw NSError(domain: "Companion", code: 2, userInfo: [NSLocalizedDescriptionKey: "Pairing could not be read. Choose Forget paired devices, then start sharing again."])
            }
            return saved
        }
        let secret = UUID().uuidString + UUID().uuidString
        try FileManager.default.createDirectory(at: pairingFile.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data(secret.utf8).write(to: pairingFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pairingFile.path)
        return secret
    }
    private static var localHostname: String? {
        guard let name = SCDynamicStoreCopyLocalHostName(nil) as String?, !name.isEmpty else { return nil }
        return name.lowercased() + ".local"
    }
    private func allowedHosts() -> Set<String> {
        var names = Self.addresses()
        if let name = Self.localHostname { names.insert(name, at: 0) }
        return Set(names.map { "\($0):\(port)" })
    }
    func pauseSharing() {
        resumeOnLaunch = false
        stop()
    }
    func forgetPairedDevices() {
        let restart = running || starting
        stop()
        do {
            if FileManager.default.fileExists(atPath: pairingFile.path) { try FileManager.default.removeItem(at: pairingFile) }
            if restart { start() }
            else { status = "Paired devices forgotten. Start sharing and scan the QR code to connect again." }
        } catch { status = "Could not forget paired devices. Sharing remains off. Please try again."; resumeOnLaunch = false }
    }

    func start() {
        guard listener == nil else { return }
        do {
            let root = dashboardRoot ?? TodayPaths.dashboard
            var page = try String(contentsOf: root.appendingPathComponent("index.html"), encoding: .utf8)
            page = page.replacingOccurrences(of: #"<script src="app.js[^\"]*"></script>"#, with: "<script src=\"companion.js\"></script>", options: .regularExpression)
            page = page.replacingOccurrences(of: #"<script src="(?:data/|../custom/)[^\"]*"></script>"#, with: "", options: .regularExpression)
            page = page.replacingOccurrences(of: "</head>", with: "<link rel=\"manifest\" href=\"manifest.json\"><link rel=\"stylesheet\" href=\"companion.css\"><meta name=\"referrer\" content=\"no-referrer\"></head>")
            html = Data(page.utf8)
            assets = [:]
            for file in ["app.js", "styles.css", "overview.css", "icons/icon-16.png", "icons/icon-32.png", "icons/icon-180.png", "icons/icon-192.png", "icons/icon-512.png"] {
                let url = root.appendingPathComponent(file)
                guard !((try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false) else { continue }
                assets["/" + file] = try? Data(contentsOf: url)
            }
            for file in ["companion.js", "companion.css", "manifest.json"] {
                assets["/" + file] = try Data(contentsOf: (resourceRoot ?? Bundle.main.resourceURL!).appendingPathComponent(file))
            }
            // Pairing survives normal pauses, relaunches and app updates on this Mac.
            token = try pairingToken()
            refreshNetworkLinks()
            let service = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
            listener = service
            starting = true
            service.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, self.listener === service else { return }
                    switch state {
                    case .ready: self.starting = false; self.running = true; self.refreshNetworkLinks()
                    case .waiting: self.status = "Waiting for local network access. Check Today’s Local Network permission and your Wi-Fi connection."
                    case .failed: self.stop(); self.status = "Could not share. Allow local network access for Today, or check whether port 8787 is in use."
                    default: break
                    }
                }
            }
            service.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            status = "Starting local sharing…"
            service.start(queue: .main)
            addressRefresh = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshNetworkLinks() }
            }
        } catch { stop(); status = error.localizedDescription }
    }
    private func refreshNetworkLinks() {
        guard !token.isEmpty else { return }
        let current = Self.addresses().map { "http://\($0):\(port)/#\(token)" }
        if links != current { links = current }
        if running {
            status = links.isEmpty ? "Waiting for Wi-Fi or Ethernet. Your pairing is remembered." : "Ready to connect on this network. Keep Today open and this Mac awake."
        }
    }
    func stop() {
        addressRefresh?.invalidate(); addressRefresh = nil
        listener?.stateUpdateHandler = nil; listener?.cancel(); listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll(); token = ""; links = []; assets = [:]
        starting = false; running = false; status = "Sharing is off. Paired devices are remembered for next time."
    }
    private func accept(_ connection: NWConnection) {
        guard connections.count < 16, listener != nil else { connection.cancel(); return }
        let id = UUID(); connections[id] = connection
        connection.start(queue: .main)
        receive(connection, id: id, buffer: Data())
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.connections.removeValue(forKey: id)?.cancel()
        }
    }
    private func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.connections[id] != nil else { return }
                var bytes = buffer; bytes.append(data ?? Data())
                guard bytes.count <= 16384, error == nil else { self.close(id); return }
                guard let boundary = bytes.range(of: Data("\r\n\r\n".utf8)) else {
                    if complete { self.close(id) } else { self.receive(connection, id: id, buffer: bytes) }; return
                }
                let header = String(decoding: bytes[..<boundary.lowerBound], as: UTF8.self)
                let lines = header.components(separatedBy: "\r\n")
                let first = lines[0].split(separator: " ")
                var fields: [String: String] = [:]
                for line in lines.dropFirst() {
                    guard let colon = line.firstIndex(of: ":") else { self.close(id); return }
                    let key = line[..<colon].lowercased()
                    guard fields[key] == nil else { self.close(id); return }
                    fields[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                }
                guard first.count == 3, fields["transfer-encoding"] == nil,
                      let length = Int(fields["content-length"] ?? "0"), (0...1024).contains(length) else { self.close(id); return }
                let body = bytes[boundary.upperBound...]
                if body.count < length {
                    if complete { self.close(id) } else { self.receive(connection, id: id, buffer: bytes) }; return
                }
                let result = self.response(method: String(first[0]), path: String(first[1]).components(separatedBy: "?")[0], fields: fields, body: String(decoding: body.prefix(length), as: UTF8.self))
                connection.send(content: result, completion: .contentProcessed { _ in
                    Task { @MainActor in self.close(id) }
                })
            }
        }
    }
    private func close(_ id: UUID) { connections.removeValue(forKey: id)?.cancel() }
    // Internal for deterministic request/security tests without opening a socket.
    func response(method: String, path: String, fields: [String: String], body: String) -> Data {
        func reply(_ code: Int, _ content: Data = Data(), type: String = "text/plain", extra: String = "") -> Data {
            var data = Data("HTTP/1.1 \(code) Response\r\nContent-Type: \(type); charset=utf-8\r\nContent-Length: \(content.count)\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nX-Frame-Options: DENY\r\nConnection: close\r\n\(extra)\r\n".utf8)
            data.append(content); return data
        }
        let cookie = fields["cookie"]?.components(separatedBy: ";").contains { $0.trimmingCharacters(in: .whitespaces) == "today_companion=" + token } == true
        guard let host = fields["host"]?.lowercased(), listener != nil, allowedHosts().contains(host), !token.isEmpty else { return reply(403) }
        if let origin = fields["origin"], origin != "http://" + host { return reply(403) }
        let authorized = cookie
        if method == "POST", path == "/pair" {
            guard fields["origin"] == "http://" + host, body == token else { return reply(403) }
            return reply(204, extra: "Set-Cookie: today_companion=\(token); Path=/; HttpOnly; SameSite=Strict; Max-Age=31536000\r\n")
        }
        guard method == "GET" else { return reply(405) }
        if path == "/" {
            if authorized { return reply(302, extra: "Location: /dashboard\r\n") }
            return reply(200, Data(Self.pairPage.utf8), type: "text/html")
        }
        // Home Screen icon fetches may not carry Safari's pairing cookie.
        // Only public app artwork/manifest bypass authentication; dashboard data never does.
        let publicAssets: Set<String> = ["/icons/icon-16.png", "/icons/icon-32.png", "/icons/icon-180.png", "/icons/icon-192.png", "/icons/icon-512.png", "/manifest.json"]
        if publicAssets.contains(path), let asset = assets[path] {
            return reply(200, asset, type: path.hasSuffix(".png") ? "image/png" : "application/manifest+json")
        }
        guard authorized else { return reply(401) }
        if path == "/dashboard" { return reply(200, html, type: "text/html", extra: "Set-Cookie: today_companion=\(token); Path=/; HttpOnly; SameSite=Strict; Max-Age=31536000\r\n") }
        if path == "/snapshot" {
            guard !snapshot.isEmpty else { return reply(503) }
            return reply(200, Data(snapshot.utf8), type: "text/javascript")
        }
        guard let asset = assets[path] else { return reply(404) }
        let type = path.hasSuffix(".js") ? "text/javascript" : path.hasSuffix(".css") ? "text/css" : path.hasSuffix(".png") ? "image/png" : "application/manifest+json"
        return reply(200, asset, type: type)
    }
    private static let pairPage = """
    <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><title>Today</title><meta name="apple-mobile-web-app-title" content="Today"><link rel="apple-touch-icon" sizes="180x180" href="/icons/icon-180.png"><link rel="icon" href="/icons/icon-32.png"><link rel="manifest" href="/manifest.json">
    <style>body{background:#191919;color:#f4f0e8;font:20px system-ui;max-width:500px;margin:15vh auto;padding:24px}h1{font-size:44px}button{background:#ff7446;color:#191919;border:0;border-radius:12px;padding:16px;font:inherit}</style>
    <h1>Your day, beside you.</h1><p id="status">Scan the QR code in Today’s Mac settings to connect a device.</p><button id="pair" hidden>Connect a device</button>
    <script>const secret=location.hash.slice(1);history.replaceState(null,'','/');if(secret){const b=document.getElementById('pair');b.hidden=false;b.onclick=async()=>{b.disabled=true;try{const r=await fetch('/pair',{method:'POST',body:secret});if(!r.ok)throw Error();location.replace('/dashboard');}catch(e){document.getElementById('status').textContent='Pairing expired or your Mac is unavailable. Scan a new QR code from Today.';b.disabled=false;}};}</script>
    """
    private static func addresses() -> [String] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0 else { return [] }
        defer { freeifaddrs(pointer) }
        var result: [String] = []; var item = pointer
        while let current = item {
            defer { item = current.pointee.ifa_next }
            let interface = current.pointee
            guard let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  String(cString: interface.ifa_name).hasPrefix("en"), interface.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
            var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &name, socklen_t(name.count), nil, 0, NI_NUMERICHOST) == 0 {
                result.append(String(cString: name))
            }
        }
        return Array(Set(result)).sorted()
    }
}

struct CompanionSettingsView: View {
    @ObservedObject var server: CompanionServer
    @State private var confirmingForget = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Device sharing").font(.headline)
                Spacer()
                Label(server.running ? "On" : server.starting ? "Starting" : "Off", systemImage: server.running ? "circle.fill" : "circle")
                    .font(.caption).foregroundStyle(server.running ? Color.green : Color.secondary)
                Button("Stop Sharing", role: .destructive) { server.pauseSharing() }
                    .disabled(!server.running && !server.starting)
            }
            Text("Stop Sharing pauses access and turns off automatic resume. Your paired devices are remembered. An offline device may still show its last received page.").font(.caption).foregroundStyle(.secondary)
            Text("Share your calendar, email summaries, and dashboard over the same Wi-Fi. Use a trusted private network: this local connection is not encrypted. Anyone with the pairing link can view your dashboard while sharing is on.").font(.caption).foregroundStyle(.secondary)
            Toggle("Resume sharing when Today opens", isOn: $server.resumeOnLaunch)
            Text("When enabled, Today shares on the connected network each time it opens. Keep it off if you use this Mac on networks you don’t trust.").font(.caption).foregroundStyle(.secondary)
            Text("Reconnect on your current network").font(.subheadline.bold())
            Text("Scan the QR code and save the dashboard to your device’s Home Screen or bookmarks. Reopen that bookmark while this Mac has the same network address. Keep both devices on the same network, this Mac awake, Today open, and sharing on.").font(.caption)
            Text("Home and work can give your Mac different IP addresses, and an address can change even on the same network. The QR code updates automatically. If a bookmark stops connecting, scan the current code and save a bookmark for that network. Pairing stays remembered, but a new address may need a scan and has separate device preferences.").font(.caption).foregroundStyle(.secondary)
            Text(server.status).font(.caption)
            if server.running, let link = server.links.first {
                if let image = qr(link) { Image(nsImage: image).interpolation(.none).resizable().frame(width: 180, height: 180).padding(8).background(.white).accessibilityLabel("Scan to pair a device with Today") }
                Text("1. Scan with your phone or tablet, then tap Connect a device.\n2. Save a bookmark. On iPhone or iPad, use Safari → Share → Add to Home Screen → Open as Web App.\nKeep this Mac awake and Today open for live updates.").font(.caption)
                ForEach(server.links, id: \.self) { link in
                    Button("Copy pairing link (\(URL(string: link)?.host ?? "Mac"))") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(link, forType: .string) }
                }
                Text("App updates keep pairing remembered. If the network address is unchanged, reopen your bookmark or tap Update dashboard. Timer, links, and display choices are saved separately for each address on your device.").font(.caption).foregroundStyle(.secondary)
                Text("For a reliable work bookmark, ask IT to reserve an IP address for this Mac. At home, your router can reserve a separate address. If a current link still won’t connect, check Today’s Local Network and firewall access; some networks block connections between devices.").font(.caption).foregroundStyle(.secondary)
            } else if server.running { Text("The QR code will appear when this Mac connects to Wi-Fi or Ethernet.").font(.caption) }
            else if server.starting { Button("Cancel sharing") { server.pauseSharing() } }
            else { Button("Start sharing") { server.start() } }
            Divider()
            Button("Forget paired devices…", role: .destructive) { confirmingForget = true }
            Text("Use this to revoke all existing pairing links and device access. Everyone will need to scan a new QR code.").font(.caption).foregroundStyle(.secondary)
        }
        .confirmationDialog("Forget all paired devices?", isPresented: $confirmingForget) {
            Button("Forget paired devices", role: .destructive) { server.forgetPairedDevices() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Existing pairing links will stop working. Connect each device again with a new QR code.") }
    }
    private func qr(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(text.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
