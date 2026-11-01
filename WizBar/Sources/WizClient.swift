import Darwin
import Foundation

/// Swift port of wiz.py: JSON over UDP on port 38899.
struct Pilot {
    var state: Bool
    var dimming: Int?
    var temp: Int?

    init?(_ json: [String: Any]?) {
        guard let result = json?["result"] as? [String: Any] else { return nil }
        state = result["state"] as? Bool ?? false
        dimming = result["dimming"] as? Int
        temp = result["temp"] as? Int
    }
}

enum WizClient {
    static let port: UInt16 = 38899
    private static let sendQueue = DispatchQueue(label: "wiz.send")

    static func clampDimming(_ v: Int) -> Int { max(10, min(100, v)) }
    static func clampTemp(_ v: Int) -> Int { max(2200, min(6500, v)) }

    // MARK: Public API (blocking calls; run them off the main thread)

    /// Fire-and-forget setPilot, in order, to every ip.
    static func setPilot(_ ips: [String], _ params: [String: Any]) {
        guard !ips.isEmpty, let data = encode("setPilot", params) else { return }
        sendQueue.async {
            let fd = makeSocket(timeout: 0.1, broadcast: false)
            defer { close(fd) }
            for ip in ips { sendTo(fd, ip, data) }
        }
    }

    /// setPilot to one light, waiting for its reply. Returns false on no response.
    @discardableResult
    static func setPilotSync(_ ip: String, _ params: [String: Any], timeout: Double = 1.0) -> Bool {
        guard let data = encode("setPilot", params) else { return false }
        let fd = makeSocket(timeout: timeout, broadcast: false)
        defer { close(fd) }
        sendTo(fd, ip, data)
        return receive(fd) != nil
    }

    static func getPilot(_ ip: String, timeout: Double = 1.0) -> Pilot? {
        guard let data = encode("getPilot", [:]) else { return nil }
        let fd = makeSocket(timeout: timeout, broadcast: false)
        defer { close(fd) }
        sendTo(fd, ip, data)
        return Pilot(receive(fd)?.json)
    }

    /// Broadcasts getPilot (global + each interface's subnet broadcast) and
    /// also unicasts to `known`, collecting replies until `timeout`.
    static func discover(known: [String] = [], timeout: Double = 2.0) -> [String: Pilot] {
        guard let data = encode("getPilot", [:]) else { return [:] }
        let fd = makeSocket(timeout: 0.25, broadcast: true)
        defer { close(fd) }
        for ip in ["255.255.255.255"] + subnetBroadcasts() + known { sendTo(fd, ip, data) }

        var found: [String: Pilot] = [:]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let (ip, json) = receive(fd), let pilot = Pilot(json) { found[ip] = pilot }
        }
        return found
    }

    // MARK: Sockets

    private static func encode(_ method: String, _ params: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: ["method": method, "params": params])
    }

    private static func makeSocket(timeout: Double, broadcast: Bool) -> Int32 {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        if broadcast {
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))
        }
        return fd
    }

    private static func sendTo(_ fd: Int32, _ ip: String, _ data: Data) {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, ip, &addr.sin_addr) == 1 else { return }
        data.withUnsafeBytes { buf in
            withUnsafePointer(to: &addr) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    _ = sendto(fd, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private static func receive(_ fd: Int32) -> (ip: String, json: [String: Any])? {
        var buf = [UInt8](repeating: 0, count: 2048)
        var from = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let n = withUnsafeMutablePointer(to: &from) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                buf.withUnsafeMutableBytes { recvfrom(fd, $0.baseAddress, $0.count, 0, sa, &len) }
            }
        }
        guard n > 0 else { return nil }
        var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &from.sin_addr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
        let json = (try? JSONSerialization.jsonObject(with: Data(buf[0..<n]))) as? [String: Any] ?? [:]
        return (String(cString: ipBuf), json)
    }

    private static func subnetBroadcasts() -> [String] {
        var result: [String] = []
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0 else { return [] }
        defer { freeifaddrs(ifap) }
        var cur = ifap
        while let ifa = cur?.pointee {
            defer { cur = ifa.ifa_next }
            let flags = Int32(ifa.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_BROADCAST != 0, flags & IFF_LOOPBACK == 0,
                  let dst = ifa.ifa_dstaddr, dst.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            var sin = dst.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &sin.sin_addr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
            result.append(String(cString: ipBuf))
        }
        return result
    }
}
