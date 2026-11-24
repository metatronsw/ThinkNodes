import Foundation
import ThinkCore
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

/// A `thinknodes` bináris kapcsolói. A run.sh ugyanezeket adja tovább, így a bináris önmagában is indítható.
struct LaunchOptions {
    enum Command: Equatable {
        case serve
        case user(name: String, role: String)
        case help
    }

    var command = Command.serve
    var http = false
    var port: Int?
    var host = "0.0.0.0"
    var rate = 33
    var test = false
    var project = "../projects"
    var tlsDirectory = ".thinknodes-tls"
    var tlsCertificate: String?
    var tlsKey: String?
    /// A `--` utáni argumentumok változtatás nélkül a Vapor `serve` parancsához kerülnek.
    var vapor: [String] = []

    var effectivePort: Int { port ?? (http ? 80 : 443) }

    static let help = """
        ThinkNodes collaboration server.

        Usage:
          thinknodes [options] [-- vapor serve arguments]
          thinknodes user NAME admin|editor|guest [--project:DIR]   (password read from stdin)

        Options:
          --help              Show this help and exit.
          --http              Serve plain HTTP instead of HTTPS (default port 80).
          --port:N            Port to listen on, 1-65535 (default 443, or 80 with --http).
          --host:ADDR         Bind address (default 0.0.0.0; use :: for IPv4 and IPv6).
          --rate:MS           Minimum interval between live drag updates in ms (default 33).
          --test              Test mode: every connecting browser gets admin rights. Never in production.
          --project:DIR       Project data directory (default ../projects, relative to the server folder).
          --tls-dir:DIR       Folder of the generated LAN certificate (default .thinknodes-tls).
                              The CA in DIR/ca.crt must be trusted on client devices.
          --tls-cert:FILE     Own TLS certificate chain (PEM); use together with --tls-key.
          --tls-key:FILE      Own TLS private key (PEM).
          --                  Pass the remaining arguments to Vapor's serve command unchanged.

        Values may be given as --port:8080 or --port=8080.
        Relative paths are resolved against the current directory, except the defaults,
        which are relative to the server folder (the folder that holds Public/).

        Environment:
          THINKNODES_CHROMIUM  Headless Chromium used for web previews (optional).
        """

    struct Problem: Error, CustomStringConvertible {
        var description: String
    }

    static func parse(_ arguments: [String]) throws -> LaunchOptions {
        var options = LaunchOptions()
        var rest = arguments[...]
        if rest.first == "user" {
            rest = rest.dropFirst()
            guard rest.count >= 2 else { throw Problem(description: "Usage: thinknodes user NAME admin|editor|guest") }
            options.command = .user(name: rest.removeFirst(), role: rest.removeFirst())
        }
        while let argument = rest.popFirst() {
            if argument == "--" {
                options.vapor = Array(rest)
                break
            }
            let (name, value) = split(argument)
            func required() throws -> String {
                guard let value, !value.isEmpty else { throw Problem(description: "\(name) needs a value, e.g. \(name):VALUE") }
                return value
            }
            func number(_ range: ClosedRange<Int>) throws -> Int {
                let text = try required()
                guard let number = Int(text), range.contains(number) else {
                    throw Problem(description: "\(name) must be a whole number between \(range.lowerBound) and \(range.upperBound).")
                }
                return number
            }
            func flag() throws {
                if value != nil { throw Problem(description: "\(name) takes no value.") }
            }
            switch name {
            case "-h", "--help": try flag(); options.command = .help
            case "--http": try flag(); options.http = true
            case "--test": try flag(); options.test = true
            case "--port": options.port = try number(1...65_535)
            case "--rate": options.rate = try number(1...999_999_999)
            case "--host": options.host = try required()
            case "--project": options.project = absolute(try required())
            case "--tls-dir": options.tlsDirectory = absolute(try required())
            case "--tls-cert": options.tlsCertificate = absolute(try required())
            case "--tls-key": options.tlsKey = absolute(try required())
            default: throw Problem(description: "Unknown option: \(argument). See thinknodes --help.")
            }
        }
        if (options.tlsCertificate == nil) != (options.tlsKey == nil) {
            throw Problem(description: "--tls-cert and --tls-key must be given together.")
        }
        return options
    }

    private static func split(_ argument: String) -> (String, String?) {
        guard argument.hasPrefix("--"), let separator = argument.firstIndex(where: { $0 == ":" || $0 == "=" }) else {
            return (argument, nil)
        }
        return (String(argument[..<separator]), String(argument[argument.index(after: separator)...]))
    }

    /// A felhasználó által megadott relatív útvonal a hívó mappájához képest értendő (a szerver később mappát vált).
    private static func absolute(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return expanded }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(expanded).standardizedFileURL.path
    }
}

enum ServerFolder {
    /// A szerver mappája (benne a Public/): a bináris mappája, vagy debug buildnél a `.build` szülője.
    /// A Vapor a Public mappát a munkakönyvtárból keresi, ezért induláskor ide váltunk.
    static func enter() {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return }
        var folder = executable.deletingLastPathComponent()
        let components = folder.pathComponents
        if let index = components.lastIndex(of: ".build") {
            folder = URL(fileURLWithPath: NSString.path(withComponents: Array(components[..<index])), isDirectory: true)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("Public").path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return }
        FileManager.default.changeCurrentDirectoryPath(folder.path)
    }
}

enum NetworkAddresses {
    /// A szerver elérési címei: a tanúsítvány alternatív nevei és a kiírt URL-ek.
    static func list(bindHost: String) -> [String] {
        guard bindHost == "0.0.0.0" || bindHost == "::" else { return [bindHost] }
        var addresses = ["localhost", "127.0.0.1"]
        if let name = localHostName() { addresses.append(name + ".local") }
        addresses += lanIPv4()
        if bindHost == "::" { addresses.append("::1") }
        var seen = Set<String>()
        return addresses.filter { seen.insert($0).inserted }
    }

    static func url(scheme: String, address: String, port: Int) -> String {
        let host = address.contains(":") ? "[\(address)]" : address
        let defaultPort = scheme == "https" ? 443 : 80
        return "\(scheme)://\(host)\(port == defaultPort ? "" : ":\(port)")/"
    }

    private static func localHostName() -> String? {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        process.arguments = ["--get", "LocalHostName"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        let name = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return process.terminationStatus == 0 && !name.isEmpty ? name : nil
        #else
        return nil
        #endif
    }

    private static func lanIPv4() -> [String] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var result = [String]()
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            cursor = entry.pointee.ifa_next
            guard let address = entry.pointee.ifa_addr, Int32(address.pointee.sa_family) == AF_INET else { continue }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
                var raw = pointer.pointee.sin_addr
                _ = inet_ntop(AF_INET, &raw, &buffer, socklen_t(INET_ADDRSTRLEN))
            }
            let text = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if !text.isEmpty, !text.hasPrefix("127."), !text.hasPrefix("169.254.") { result.append(text) }
        }
        return result
    }
}
