import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

// Turkish when the system language is Turkish, English otherwise.
let isTurkish = Locale.preferredLanguages.first?.hasPrefix("tr") ?? false
func t(_ tr: String, _ en: String) -> String { isTurkish ? tr : en }

enum Status {
    case waiting
    case ok(String)
    case error(String)

    var text: String {
        switch self {
        case .waiting: t("Bekliyor", "Waiting")
        case .ok(let s): "✓ " + s
        case .error(let s): t("Hata: ", "Error: ") + s
        }
    }

    var color: Color {
        switch self {
        case .waiting: .secondary
        case .ok: .green
        case .error: .red
        }
    }
}

struct Item: Identifiable {
    let id = UUID()
    let url: URL
    var status: Status = .waiting
}

@MainActor
final class Model: ObservableObject {
    @Published var items: [Item] = []
    @Published var quality: Double = 75
    @Published var target: URL?
    @Published var running = false
    @Published var done = 0

    static let exts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "gif", "webp"]

    var cwebp: String? {
        ["/opt/homebrew/bin/cwebp", "/usr/local/bin/cwebp"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func add(_ urls: [URL]) {
        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                add(files)
            } else if Self.exts.contains(url.pathExtension.lowercased()), !items.contains(where: { $0.url == url }) {
                items.append(Item(url: url))
            }
        }
    }

    func pickFiles() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = true
        p.allowedContentTypes = [.image]
        if p.runModal() == .OK { add(p.urls) }
    }

    func pickTarget() {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.canCreateDirectories = true
        p.prompt = t("Seç", "Choose")
        if p.runModal() == .OK { target = p.url }
    }

    func convert() {
        guard let target, let cwebp else { return }
        running = true
        done = 0
        let q = Int(quality)
        let jobs = items.enumerated().map { ($0.offset, $0.element.url) }
        for i in items.indices { items[i].status = .waiting }
        Task.detached {
            await withTaskGroup(of: Void.self) { group in
                var it = jobs.makeIterator()
                let limit = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
                func next() -> Bool {
                    guard let (idx, url) = it.next() else { return false }
                    group.addTask {
                        let r = Self.convertOne(url: url, target: target, quality: q, cwebp: cwebp)
                        await MainActor.run {
                            self.items[idx].status = r
                            self.done += 1
                        }
                    }
                    return true
                }
                for _ in 0..<limit where next() {}
                while await group.next() != nil { _ = next() }
            }
            await MainActor.run { self.running = false }
        }
    }

    nonisolated static func convertOne(url: URL, target: URL, quality: Int, cwebp: String) -> Status {
        // Decode with ImageIO (handles HEIC and EXIF orientation), write temp PNG, encode with cwebp.
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return .error(t("okunamadı", "could not read")) }
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(w, h, 1),
        ]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return .error(t("çözülemedi", "could not decode")) }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard let dest = CGImageDestinationCreateWithURL(tmp as CFURL, UTType.png.identifier as CFString, 1, nil) else { return .error(t("geçici dosya", "temporary file")) }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { return .error(t("geçici dosya", "temporary file")) }

        var out = target.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".webp")
        var n = 1
        while FileManager.default.fileExists(atPath: out.path) {
            out = target.appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-\(n).webp")
            n += 1
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cwebp)
        p.arguments = ["-quiet", "-q", String(quality), "-mt", tmp.path, "-o", out.path]
        do { try p.run(); p.waitUntilExit() } catch { return .error(t("cwebp çalışmadı", "cwebp failed to run")) }
        guard p.terminationStatus == 0 else { return .error(t("dönüştürülemedi", "conversion failed")) }
        let before = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let after = (try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let f = ByteCountFormatter()
        return .ok("\(f.string(fromByteCount: Int64(before))) → \(f.string(fromByteCount: Int64(after)))")
    }
}

struct ContentView: View {
    @StateObject var m = Model()
    @State var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if m.cwebp == nil {
                Text(t("cwebp bulunamadı. Terminalde çalıştırın: brew install webp", "cwebp not found. Run in Terminal: brew install webp")).foregroundStyle(.red)
            }
            HStack {
                Button(t("Fotoğraf Ekle…", "Add Photos…")) { m.pickFiles() }
                Button(t("Listeyi Temizle", "Clear List")) { m.items.removeAll() }.disabled(m.items.isEmpty || m.running)
                Spacer()
                Text("\(m.items.count) " + t("dosya", m.items.count == 1 ? "file" : "files")).foregroundStyle(.secondary)
            }
            List {
                ForEach(m.items) { item in
                    HStack {
                        Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(item.status.text).foregroundStyle(item.status.color)
                    }
                }
                .onDelete { m.items.remove(atOffsets: $0) }
            }
            .overlay {
                if m.items.isEmpty {
                    Text(t("Fotoğrafları ya da klasörleri buraya sürükleyin", "Drag photos or folders here")).foregroundStyle(.secondary)
                }
            }
            .border(hover ? Color.accentColor : .clear, width: 2)
            .onDrop(of: [.fileURL], isTargeted: $hover) { providers in
                for pr in providers {
                    _ = pr.loadObject(ofClass: URL.self) { url, _ in
                        if let url { Task { @MainActor in m.add([url]) } }
                    }
                }
                return true
            }
            HStack {
                Text(t("Kalite", "Quality") + ": \(Int(m.quality))").frame(width: 90, alignment: .leading)
                Slider(value: $m.quality, in: 1...100, step: 1)
            }
            HStack {
                Button(t("Hedef Klasör…", "Output Folder…")) { m.pickTarget() }
                Text(m.target?.path ?? t("Seçilmedi", "Not selected")).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                Spacer()
                if let folder = m.target {
                    Button(t("Finder'da Aç", "Show in Finder")) { NSWorkspace.shared.open(folder) }
                }
            }
            HStack {
                if m.running {
                    ProgressView(value: Double(m.done), total: Double(max(m.items.count, 1)))
                } else {
                    Spacer()
                }
                Button(t("WebP'ye Çevir", "Convert to WebP")) { m.convert() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(m.items.isEmpty || m.target == nil || m.running || m.cwebp == nil)
            }
            HStack {
                Spacer()
                Link("© 2026 Murat Gökoğlu · muratgokoglu.com", destination: URL(string: "https://muratgokoglu.com")!)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 460)
    }
}

@main
struct WebPConverterApp: App {
    var body: some Scene {
        WindowGroup(t("WebP Dönüştürücü", "WebP Converter")) { ContentView() }
            .commands {
                CommandGroup(replacing: .appInfo) {
                    Button(t("WebP Dönüştürücü Hakkında", "About WebP Converter")) {
                        NSApplication.shared.orderFrontStandardAboutPanel(options: [
                            .credits: NSAttributedString(string: t("Yayıncı", "Publisher") + ": Murat Gökoğlu\nmuratgokoglu.com"),
                        ])
                    }
                }
            }
    }
}
