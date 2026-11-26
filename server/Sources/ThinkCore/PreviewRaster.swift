import Foundation

/// A főoldali projektkártyák háttérképe: a munkalap előnézete (SVG vagy a beállított előnézeti kép) fix méretű, már
/// elmosott `.webp` képként. A kártya csak méretezi (CSS szűrő nélkül): a böngészőnek nem kell a nagy SVG-t (sok
/// beágyazott HTML-lel) feldolgoznia és minden kártyán elmosást festenie.
///
/// Külső eszközök: `rsvg-convert` (librsvg; Fedora: librsvg2-tools, macOS: MacPorts / Homebrew librsvg) és `cwebp`
/// (libwebp; Fedora: libwebp-tools). Ha valamelyik hiányzik vagy a konvertálás nem sikerül, a hívó az SVG-előnézetet
/// adja (`render` nil-t ad). A librsvg a dobozokba ágyazott HTML-t (foreignObject: táblázat, szövegfájl tartalma) nem
/// rajzolja ki – elmosott, halvány háttérként ez nem zavaró; a dobozok, vonalak, címkék és a háttér látszanak.
package enum PreviewRaster {
    /// A kép mérete képpontban (16:9, mint a kártya). A kártya (~363 × 204 CSS-képpont) felnagyítja: elmosott háttérként
    /// a kisebb felbontás nem látszik, a fájl viszont kicsi (néhány KB).
    package static let width = 320, height = 180
    /// Az elmosás (a korábbi CSS `blur(1px)` a kártya méretén; a kártya a képet ~1,2-szeresére nagyítja).
    static let blur = 1.0
    /// Túlnyúlás: a kép ennyivel nagyobb vásznon készül és mosódik el, a WebP ebből vágja ki a közepét. Így az elmosás
    /// pereme (a vászon szélén a librsvg átlátszóval mos el) a levágott sávba esik, a kép teljesen fedett.
    static let margin = 8
    static let quality = 70

    /// A két eszköz útvonala, ha mindkettő megvan.
    static let tools: (rsvg: String, cwebp: String)? = {
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let folders = path + ["/opt/local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        func find(_ name: String) -> String? {
            folders.map { $0 + "/" + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
        }
        guard let rsvg = find("rsvg-convert"), let cwebp = find("cwebp") else { return nil }
        return (rsvg, cwebp)
    }()

    package static var available: Bool { tools != nil }

    /// `source`: SVG-előnézet vagy előnézeti kép (PNG, JPEG, SVG …); `target`: az elkészült `.webp` helye.
    @discardableResult
    package static func render(source: URL, to target: URL) -> Bool {
        guard let tools, let content = try? Data(contentsOf: source) else { return false }
        let manager = FileManager.default
        // A forrás data URI-ként a burkoló SVG-ben: nincs ideiglenes mappa, és a librsvg semmilyen más fájlt nem olvas.
        let types = ["svg": "image/svg+xml", "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif"]
        guard let type = types[source.pathExtension.lowercased()] else { return false }
        let href = "data:" + type + ";base64," + content.base64EncodedString()
        // A forrás kitölti a túlnyúlással megnövelt vásznat (levágva, középre igazítva), elmosva; a WebP a közepét vágja ki.
        let (canvasWidth, canvasHeight) = (width + 2 * margin, height + 2 * margin)
        let wrapper = """
            <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="\(canvasWidth)" height="\(canvasHeight)" viewBox="0 0 \(canvasWidth) \(canvasHeight)">
              <defs><filter id="blur" x="-5%" y="-5%" width="110%" height="110%" color-interpolation-filters="sRGB"><feGaussianBlur stdDeviation="\(blur)"/></filter></defs>
              <g filter="url(#blur)"><image width="\(canvasWidth)" height="\(canvasHeight)" preserveAspectRatio="xMidYMid slice" href="\(href)" xlink:href="\(href)"/></g>
            </svg>
            """
        // rsvg-convert (SVG → PNG a szabványos kimenetre) | cwebp (PNG a bemenetről → a közép kivágva → WebP, egy statikus
        // képkocka; a teljesen fedett képhez nem tesz átlátszósági réteget).
        // A WebP először egy ideiglenes névre készül a cél mellett, onnan atomi cserével kerül a helyére.
        let staged = target.deletingLastPathComponent().appendingPathComponent(".tmp-" + UUID().uuidString + ".webp")
        defer { try? manager.removeItem(at: staged) }
        guard pipeline(tools, svg: Data(wrapper.utf8), output: staged), manager.fileExists(atPath: staged.path) else { return false }
        do {
            if manager.fileExists(atPath: target.path) { _ = try manager.replaceItemAt(target, withItemAt: staged) }
            else { try manager.moveItem(at: staged, to: target) }
        } catch { return false }
        return true
    }

    /// Háttérben (a kérés nem vár rá): ugyanarra a célra egyszerre csak egy konvertálás fut.
    package static func refresh(source: URL, to target: URL) {
        guard running.withLock({ $0.insert(target.path).inserted }) else { return }
        DispatchQueue.global(qos: .utility).async {
            render(source: source, to: target)
            running.withLock { _ = $0.remove(target.path) }
        }
    }
    private static let running = Locked<Set<String>>([])

    /// A két program csővel összekötve, legfeljebb 20 mp-ig; siker: mindkettő 0-s kilépési kóddal.
    private static func pipeline(_ tools: (rsvg: String, cwebp: String), svg: Data, output: URL) -> Bool {
        let render = Process(), encode = Process()
        render.executableURL = URL(fileURLWithPath: tools.rsvg)
        render.arguments = ["-w", String(width + 2 * margin), "-h", String(height + 2 * margin), "-f", "png"]
        encode.executableURL = URL(fileURLWithPath: tools.cwebp)
        encode.arguments = ["-quiet", "-q", String(quality), "-m", "4", "-crop", String(margin), String(margin), String(width), String(height),
                            "-o", output.path, "--", "-"]
        let input = Pipe(), between = Pipe()
        render.standardInput = input
        render.standardOutput = between
        render.standardError = FileHandle.nullDevice
        encode.standardInput = between
        encode.standardOutput = FileHandle.nullDevice
        encode.standardError = FileHandle.nullDevice
        let finished = DispatchGroup()
        for process in [render, encode] {
            finished.enter()
            process.terminationHandler = { _ in finished.leave() }
        }
        do { try render.run() } catch { return false }
        do { try encode.run() } catch { render.terminate(); return false }
        // A szülő példányai a cső végeiből: a cwebp csak akkor kap fájlvéget, ha az írási végen senki más nincs.
        try? between.fileHandleForWriting.close()
        try? between.fileHandleForReading.close()
        try? input.fileHandleForReading.close()
        let writer = input.fileHandleForWriting
        DispatchQueue.global(qos: .utility).async {
            try? writer.write(contentsOf: svg)
            try? writer.close()
        }
        if finished.wait(timeout: .now() + 20) == .timedOut {
            render.terminate()
            encode.terminate()
            return false
        }
        return [render, encode].allSatisfy { $0.terminationReason == .exit && $0.terminationStatus == 0 }
    }
}

/// Egyszerű zárolt érték (a háttérben futó konvertálások nyilvántartásához).
final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()
    init(_ value: Value) { self.value = value }
    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
