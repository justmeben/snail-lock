import SwiftUI
import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

// MARK: - Config

let configFile = ("~/.snail_lock.conf" as NSString).expandingTildeInPath

struct LockConfig: Equatable {
    var password: String
    var message: String
    var unlockIcon: String
    var iconSet: [String]
    var lockHotkey: String
    var imagePath: String     // empty = disabled
    var imageCount: Int       // 0 = disabled
    var imageSpin: Bool
}

let defaultIconSet = ["🐌", "🐌", "🐌", "🐚", "🐛", "🌿", "🍃", "🌱", "🍄", "🪱"]
let defaultUnlockIcon = "🐌"
let defaultLockHotkey = "option+l"
let defaultImageCount = 5
let defaultImageSpin = false

func parseBool(_ raw: String) -> Bool {
    let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
    return s == "true" || s == "yes" || s == "1" || s == "on"
}

func parseIconSet(_ raw: String) -> [String] {
    let separators = CharacterSet(charactersIn: ",;|") .union(.whitespacesAndNewlines)
    return raw.components(separatedBy: separators)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

func loadConfig() -> LockConfig {
    var password = "slug"
    var message = "brb"
    var unlockIcon = defaultUnlockIcon
    var iconSet = defaultIconSet
    var lockHotkey = defaultLockHotkey
    var imagePath = ""
    var imageCount = defaultImageCount
    var imageSpin = defaultImageSpin
    if let contents = try? String(contentsOfFile: configFile, encoding: .utf8) {
        for rawLine in contents.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "password":     if !value.isEmpty { password = value }
            case "message":      if !value.isEmpty { message = value }
            case "unlock_icon":  if !value.isEmpty { unlockIcon = value }
            case "icon_set":
                let parsed = parseIconSet(value)
                if !parsed.isEmpty { iconSet = parsed }
            case "lock_hotkey":  if !value.isEmpty { lockHotkey = value }
            case "image_path":   imagePath = (value as NSString).expandingTildeInPath
            case "image_count":  if let n = Int(value) { imageCount = max(0, n) }
            case "image_spin":   imageSpin = parseBool(value)
            default: break
            }
        }
    }
    return LockConfig(
        password: password, message: message, unlockIcon: unlockIcon,
        iconSet: iconSet, lockHotkey: lockHotkey,
        imagePath: imagePath, imageCount: imageCount, imageSpin: imageSpin
    )
}

/// Writes config back, preserving existing comments / unknown lines.
func saveConfig(_ cfg: LockConfig) {
    let updates: [String: String] = [
        "password":     cfg.password,
        "message":      cfg.message,
        "unlock_icon":  cfg.unlockIcon,
        "icon_set":     cfg.iconSet.joined(separator: ", "),
        "lock_hotkey":  cfg.lockHotkey,
        "image_path":   cfg.imagePath,
        "image_count":  String(cfg.imageCount),
        "image_spin":   cfg.imageSpin ? "true" : "false",
    ]
    var seen = Set<String>()
    var lines: [String] = []

    if let contents = try? String(contentsOfFile: configFile, encoding: .utf8) {
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                lines.append(line); continue
            }
            guard let eq = trimmed.firstIndex(of: "=") else {
                lines.append(line); continue
            }
            let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            if let v = updates[key] {
                lines.append("\(key)=\(v)")
                seen.insert(key)
            } else {
                lines.append(line)
            }
        }
    }

    for (k, v) in updates where !seen.contains(k) {
        lines.append("\(k)=\(v)")
    }

    let output = lines.joined(separator: "\n") + "\n"
    do {
        try output.write(toFile: configFile, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFile)
    } catch {
        NSLog("snail-lock: saveConfig failed: \(error)")
    }
}

// MARK: - Hotkey support (Carbon)

let keyCodeMap: [String: UInt32] = [
    "a": UInt32(kVK_ANSI_A), "b": UInt32(kVK_ANSI_B), "c": UInt32(kVK_ANSI_C),
    "d": UInt32(kVK_ANSI_D), "e": UInt32(kVK_ANSI_E), "f": UInt32(kVK_ANSI_F),
    "g": UInt32(kVK_ANSI_G), "h": UInt32(kVK_ANSI_H), "i": UInt32(kVK_ANSI_I),
    "j": UInt32(kVK_ANSI_J), "k": UInt32(kVK_ANSI_K), "l": UInt32(kVK_ANSI_L),
    "m": UInt32(kVK_ANSI_M), "n": UInt32(kVK_ANSI_N), "o": UInt32(kVK_ANSI_O),
    "p": UInt32(kVK_ANSI_P), "q": UInt32(kVK_ANSI_Q), "r": UInt32(kVK_ANSI_R),
    "s": UInt32(kVK_ANSI_S), "t": UInt32(kVK_ANSI_T), "u": UInt32(kVK_ANSI_U),
    "v": UInt32(kVK_ANSI_V), "w": UInt32(kVK_ANSI_W), "x": UInt32(kVK_ANSI_X),
    "y": UInt32(kVK_ANSI_Y), "z": UInt32(kVK_ANSI_Z),
    "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2),
    "3": UInt32(kVK_ANSI_3), "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5),
    "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8),
    "9": UInt32(kVK_ANSI_9),
    "space": UInt32(kVK_Space),
    "return": UInt32(kVK_Return), "enter": UInt32(kVK_Return),
    "escape": UInt32(kVK_Escape), "esc": UInt32(kVK_Escape),
    "tab": UInt32(kVK_Tab),
    "delete": UInt32(kVK_Delete), "backspace": UInt32(kVK_Delete),
    "f1": UInt32(kVK_F1),  "f2": UInt32(kVK_F2),  "f3": UInt32(kVK_F3),
    "f4": UInt32(kVK_F4),  "f5": UInt32(kVK_F5),  "f6": UInt32(kVK_F6),
    "f7": UInt32(kVK_F7),  "f8": UInt32(kVK_F8),  "f9": UInt32(kVK_F9),
    "f10": UInt32(kVK_F10), "f11": UInt32(kVK_F11), "f12": UInt32(kVK_F12),
]

func keyNameForKeyCode(_ kc: UInt16) -> String? {
    for (name, code) in keyCodeMap where code == UInt32(kc) {
        // Prefer a canonical name when multiple aliases exist.
        if ["enter", "esc", "backspace"].contains(name) { continue }
        return name
    }
    return nil
}

func parseCombo(_ combo: String) -> (keyCode: UInt32, modMask: UInt32)? {
    let tokens = combo.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
    guard !tokens.isEmpty else { return nil }
    var modMask: UInt32 = 0
    var key: String?
    for t in tokens {
        switch t {
        case "cmd", "command":       modMask |= UInt32(cmdKey)
        case "shift":                modMask |= UInt32(shiftKey)
        case "option", "alt", "opt": modMask |= UInt32(optionKey)
        case "ctrl", "control":      modMask |= UInt32(controlKey)
        default:                     key = t
        }
    }
    guard let k = key, let kc = keyCodeMap[k] else { return nil }
    return (kc, modMask)
}

func prettyCombo(_ combo: String) -> String {
    let parts = combo.lowercased().split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }
    var out: [String] = []
    for p in parts {
        switch p {
        case "cmd", "command":       out.append("⌘")
        case "shift":                out.append("⇧")
        case "option", "alt", "opt": out.append("⌥")
        case "ctrl", "control":      out.append("⌃")
        case "return", "enter":      out.append("↩")
        case "escape", "esc":        out.append("⎋")
        case "tab":                  out.append("⇥")
        case "space":                out.append("␣")
        case "delete", "backspace":  out.append("⌫")
        default:                     out.append(p.uppercased())
        }
    }
    return out.joined()
}

/// Wraps Carbon RegisterEventHotKey. Only one hotkey at a time.
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    /// Static so the @convention(c) callback can dispatch — that callback can't capture.
    static var sharedCallback: (() -> Void)?
    static var isSuppressed: Bool = false

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var ref: EventHandlerRef?
        InstallEventHandler(GetApplicationEventTarget(), { (_, _, _) -> OSStatus in
            if !HotkeyManager.isSuppressed {
                HotkeyManager.sharedCallback?()
            }
            return noErr
        }, 1, &spec, nil, &ref)
        eventHandlerRef = ref
    }

    @discardableResult
    func register(_ combo: String, onTrigger: @escaping () -> Void) -> Bool {
        unregister()
        guard let parsed = parseCombo(combo) else { return false }

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x534E4C4B), id: 1) // 'SNLK'
        let status = RegisterEventHotKey(parsed.keyCode, parsed.modMask, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let r = ref else { return false }
        hotKeyRef = r
        HotkeyManager.sharedCallback = onTrigger
        return true
    }

    func unregister() {
        if let r = hotKeyRef {
            UnregisterEventHotKey(r)
            hotKeyRef = nil
        }
        HotkeyManager.sharedCallback = nil
    }
}

// MARK: - ConfigStore (observable, debounced save)

final class Debouncer {
    private var workItem: DispatchWorkItem?
    func schedule(after seconds: Double, _ block: @escaping () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem(block: block)
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }
}

final class ConfigStore: ObservableObject {
    @Published var config: LockConfig
    private let debouncer = Debouncer()
    var onChange: ((LockConfig) -> Void)?

    init() { config = loadConfig() }

    func scheduleSave() {
        let snapshot = config
        debouncer.schedule(after: 0.25) { [weak self] in
            saveConfig(snapshot)
            self?.onChange?(snapshot)
        }
    }
}

// MARK: - Lock-screen password field

struct WhiteSecureField: View {
    @Binding var text: String
    var onSubmit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .foregroundColor(.clear)
                .tint(.clear)
                .accentColor(.clear)
                .font(.system(size: 26, weight: .medium, design: .monospaced))
                .focused($focused)
                .onSubmit(onSubmit)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        focused = true
                    }
                }

            HStack {
                if text.isEmpty {
                    Text("password").foregroundColor(.white.opacity(0.45))
                } else {
                    Text(String(repeating: "•", count: text.count))
                        .foregroundColor(.white)
                        .tracking(4)
                }
            }
            .font(.system(size: 26, weight: .bold, design: .monospaced))
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}

struct Snail: Identifiable {
    let id = UUID()
    var emoji: String
    var x: CGFloat
    var y: CGFloat
    var dx: CGFloat
    var dy: CGFloat
    var size: CGFloat
    var rotation: Double
    var spin: Double
}

struct ImageSprite: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var dx: CGFloat
    var dy: CGFloat
    var size: CGFloat
    var rotation: Double
    var spin: Double
}

/// SwiftUI wrapper around NSImageView so animated GIFs play back instead of
/// rendering as static first frames (which `Image(nsImage:)` does).
struct AnimatedImageView: NSViewRepresentable {
    let nsImage: NSImage?

    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.animates = true
        v.imageScaling = .scaleProportionallyUpOrDown
        v.image = nsImage
        return v
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        if nsView.image !== nsImage {
            nsView.image = nsImage
            nsView.animates = true
        }
    }
}

struct LockView: View {
    let screenSize: CGSize
    let message: String
    let unlockIcon: String
    let iconSet: [String]
    let imagePath: String
    let imageCount: Int
    let imageSpin: Bool
    let onUnlock: () -> Void

    @State private var password: String = ""
    @State private var wrong = false
    @State private var snails: [Snail] = []
    @State private var imageSprites: [ImageSprite] = []
    @State private var loadedImage: NSImage? = nil
    @State private var shake: CGFloat = 0
    @State private var showPrompt: Bool = false
    @State private var bigSnailPulse: Bool = false
    @State private var hue: Double = .random(in: 0...1)
    let timer = Timer.publish(every: 0.033, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hue: hue, saturation: 0.65, brightness: 0.35),
                    Color(hue: (hue + 0.18).truncatingRemainder(dividingBy: 1.0), saturation: 0.7, brightness: 0.20),
                    Color(hue: (hue + 0.42).truncatingRemainder(dividingBy: 1.0), saturation: 0.6, brightness: 0.30)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.linear(duration: 0.033), value: hue)

            ForEach(snails) { snail in
                Text(snail.emoji)
                    .font(.system(size: snail.size))
                    .rotationEffect(.degrees(snail.rotation))
                    .position(x: snail.x, y: snail.y)
                    .scaleEffect(x: snail.emoji == "🐌" && snail.dx < 0 ? -1 : 1, y: 1)
                    .opacity(0.9)
            }

            if let img = loadedImage {
                ForEach(imageSprites) { sprite in
                    AnimatedImageView(nsImage: img)
                        .frame(width: sprite.size, height: sprite.size)
                        .rotationEffect(.degrees(sprite.rotation))
                        .position(x: sprite.x, y: sprite.y)
                }
            }

            VStack(spacing: 0) {
                Spacer()
                Text(message)
                    .font(.system(size: min(screenSize.width / CGFloat(max(8, message.count)) * 1.6, screenSize.height * 0.18), weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.3)
                    .lineLimit(3)
                    .padding(.horizontal, 60)
                    .shadow(color: .black.opacity(0.6), radius: 12, x: 0, y: 4)
                Spacer()

                ZStack {
                    if showPrompt {
                        VStack(spacing: 10) {
                            WhiteSecureField(text: $password, onSubmit: tryUnlock)
                                .frame(width: 360, height: 50)
                                .padding(.horizontal, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.black.opacity(0.55))
                                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.6), lineWidth: 2))
                                )
                                .offset(x: shake)
                            if wrong {
                                Text("nope. try again.").foregroundColor(.red).font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .transition(.opacity.combined(with: .scale))
                    } else {
                        Text(unlockIcon)
                            .font(.system(size: 160))
                            .scaleEffect(bigSnailPulse ? 1.05 : 1.0)
                            .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 8)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    showPrompt = true
                                }
                                password = ""
                                wrong = false
                            }
                            .onAppear {
                                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                                    bigSnailPulse = true
                                }
                            }
                            .transition(.opacity.combined(with: .scale))
                    }
                }
                .frame(height: 180)
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            spawnSnails()
            loadImageIfNeeded()
            spawnImageSprites()
        }
        .onReceive(timer) { _ in tick() }
    }

    func loadImageIfNeeded() {
        guard !imagePath.isEmpty, imageCount > 0 else { return }
        if FileManager.default.fileExists(atPath: imagePath) {
            loadedImage = NSImage(contentsOfFile: imagePath)
        }
    }

    func spawnImageSprites() {
        guard loadedImage != nil, imageCount > 0 else { return }
        imageSprites = (0..<imageCount).map { _ in
            ImageSprite(
                x: .random(in: 0...screenSize.width),
                y: .random(in: 0...screenSize.height),
                dx: .random(in: -2.5...2.5),
                dy: .random(in: -1.8...1.8),
                size: .random(in: 90...170),
                rotation: .random(in: -25...25),
                spin: imageSpin ? (.random(in: 0.25...0.9) * (Bool.random() ? 1 : -1)) : 0
            )
        }
    }

    func spawnSnails() {
        let count = max(20, Int(screenSize.width * screenSize.height / 50000))
        let pool = iconSet.isEmpty ? defaultIconSet : iconSet
        snails = (0..<count).map { _ in
            let emoji = pool.randomElement()!
            return Snail(
                emoji: emoji,
                x: .random(in: 0...screenSize.width),
                y: .random(in: 0...screenSize.height),
                dx: .random(in: -3.0...3.0),
                dy: .random(in: -2.0...2.0),
                size: .random(in: 28...80),
                rotation: .random(in: -30...30),
                spin: emoji == "🐌" ? 0 : .random(in: -2.0...2.0)
            )
        }
    }

    func tick() {
        hue = (hue + 0.005).truncatingRemainder(dividingBy: 1.0)
        for i in snails.indices {
            snails[i].x += snails[i].dx
            snails[i].y += snails[i].dy
            snails[i].rotation += snails[i].spin == 0 ? Double(snails[i].dx) * 0.5 : snails[i].spin
            if snails[i].x < -40 { snails[i].x = -40; snails[i].dx = abs(snails[i].dx) }
            if snails[i].x > screenSize.width + 40 { snails[i].x = screenSize.width + 40; snails[i].dx = -abs(snails[i].dx) }
            if snails[i].y < -40 { snails[i].y = -40; snails[i].dy = abs(snails[i].dy) }
            if snails[i].y > screenSize.height + 40 { snails[i].y = screenSize.height + 40; snails[i].dy = -abs(snails[i].dy) }
        }
        for i in imageSprites.indices {
            imageSprites[i].x += imageSprites[i].dx
            imageSprites[i].y += imageSprites[i].dy
            imageSprites[i].rotation += imageSprites[i].spin
            let half = imageSprites[i].size / 2
            if imageSprites[i].x < -half { imageSprites[i].x = -half; imageSprites[i].dx = abs(imageSprites[i].dx) }
            if imageSprites[i].x > screenSize.width + half { imageSprites[i].x = screenSize.width + half; imageSprites[i].dx = -abs(imageSprites[i].dx) }
            if imageSprites[i].y < -half { imageSprites[i].y = -half; imageSprites[i].dy = abs(imageSprites[i].dy) }
            if imageSprites[i].y > screenSize.height + half { imageSprites[i].y = screenSize.height + half; imageSprites[i].dy = -abs(imageSprites[i].dy) }
        }
    }

    func tryUnlock() {
        if password == loadConfig().password {
            onUnlock()
        } else {
            wrong = true
            password = ""
            withAnimation(.default) { shake = 10 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.default) { shake = -10 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.default) { shake = 0 }
                }
            }
        }
    }
}

class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Lock controller

final class LockController {
    private(set) var windows: [NSWindow] = []
    private var savedPresentationOptions: NSApplication.PresentationOptions = []
    var isLocked: Bool { !windows.isEmpty }

    func present() {
        guard !isLocked else { return }
        let cfg = loadConfig()
        savedPresentationOptions = NSApp.presentationOptions
        NSApp.presentationOptions = [
            .hideDock, .hideMenuBar,
            .disableProcessSwitching, .disableForceQuit,
            .disableSessionTermination, .disableHideApplication,
            .disableAppleMenu,
        ]

        for (idx, screen) in NSScreen.screens.enumerated() {
            let window = KeyableWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = true
            window.hasShadow = false
            window.backgroundColor = .black
            window.isMovable = false
            window.acceptsMouseMovedEvents = true
            window.contentView = NSHostingView(rootView: LockView(
                screenSize: screen.frame.size,
                message: cfg.message,
                unlockIcon: cfg.unlockIcon,
                iconSet: cfg.iconSet,
                imagePath: cfg.imagePath,
                imageCount: cfg.imageCount,
                imageSpin: cfg.imageSpin,
                onUnlock: { [weak self] in self?.dismiss() }
            ))
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            if idx == 0 { window.makeKey() }
            windows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        guard isLocked else { return }
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        NSApp.presentationOptions = savedPresentationOptions
    }
}

// MARK: - Hotkey recorder (NSView wrapped in SwiftUI)

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var combo: String

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let v = HotkeyRecorderNSView()
        v.onCapture = { newCombo in
            DispatchQueue.main.async { self.combo = newCombo }
        }
        v.currentCombo = combo
        return v
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        nsView.currentCombo = combo
    }
}

final class HotkeyRecorderNSView: NSView {
    var currentCombo: String = "" { didSet { needsDisplay = true } }
    var isRecording: Bool = false {
        didSet {
            needsDisplay = true
            HotkeyManager.isSuppressed = isRecording
        }
    }
    var onCapture: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 220, height: 28) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { isRecording = false }
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }

        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            return
        }

        let flags = event.modifierFlags
        var parts: [String] = []
        if flags.contains(.command) { parts.append("cmd") }
        if flags.contains(.shift)   { parts.append("shift") }
        if flags.contains(.option)  { parts.append("option") }
        if flags.contains(.control) { parts.append("control") }
        // Require at least one modifier so we don't bind plain letters.
        guard !parts.isEmpty else { return }

        guard let keyName = keyNameForKeyCode(event.keyCode) else { return }
        parts.append(keyName)
        let combo = parts.joined(separator: "+")
        currentCombo = combo
        isRecording = false
        onCapture?(combo)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bg = isRecording
            ? NSColor.controlAccentColor.withAlphaComponent(0.18)
            : NSColor.unemphasizedSelectedTextBackgroundColor.withAlphaComponent(0.5)
        bg.setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        path.fill()

        let stroke = isRecording ? NSColor.controlAccentColor : NSColor.separatorColor
        stroke.setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let text: String
        if isRecording {
            text = "Press combo… (esc to cancel)"
        } else if currentCombo.isEmpty {
            text = "Click to set"
        } else {
            text = prettyCombo(currentCombo)
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]
        let attrText = NSAttributedString(string: text, attributes: attrs)
        let size = attrText.size()
        let textRect = NSRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        attrText.draw(in: textRect)
    }
}

// MARK: - Settings view

struct SettingsView: View {
    @ObservedObject var store: ConfigStore
    var onLockNow: () -> Void
    @FocusState private var focusedField: SettingsField?

    enum SettingsField: Hashable {
        case password, message, unlockIcon, iconSet
    }

    private func openEmojiPicker(focus: SettingsField) {
        focusedField = focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.orderFrontCharacterPalette(nil)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                groupTitle("Lock screen")

                labeled("Password") {
                    SecureField("password", text: $store.config.password)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .password)
                }

                labeled("Message") {
                    TextField("Shown big to bystanders", text: $store.config.message)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .message)
                }

                labeled("Unlock icon") {
                    HStack(spacing: 10) {
                        TextField("🐌", text: $store.config.unlockIcon)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .focused($focusedField, equals: .unlockIcon)
                        Text(store.config.unlockIcon.isEmpty ? defaultUnlockIcon : store.config.unlockIcon)
                            .font(.system(size: 32))
                        Spacer()
                        Button {
                            openEmojiPicker(focus: .unlockIcon)
                        } label: {
                            Image(systemName: "face.smiling")
                        }
                        .help("Open emoji picker")
                        Button("Reset") { store.config.unlockIcon = defaultUnlockIcon }
                    }
                }

                labeled("Background icons") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            TextField("", text: Binding(
                                get: { store.config.iconSet.joined(separator: ", ") },
                                set: { store.config.iconSet = parseIconSet($0) }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .iconSet)
                            Button {
                                openEmojiPicker(focus: .iconSet)
                            } label: {
                                Image(systemName: "face.smiling")
                            }
                            .help("Open emoji picker")
                            Button("Reset") { store.config.iconSet = defaultIconSet }
                        }
                        Text(store.config.iconSet.prefix(20).joined(separator: " "))
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                        Text("Comma- or space-separated. Repeats act as weights.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider().padding(.vertical, 4)

                groupTitle("Custom image")

                labeled("Image (PNG / JPG / GIF)") {
                    HStack(spacing: 8) {
                        TextField("/path/to/file.gif", text: $store.config.imagePath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse…") { pickImage() }
                        Button("Clear") { store.config.imagePath = "" }
                            .disabled(store.config.imagePath.isEmpty)
                    }
                }

                labeled("How many to spawn: \(store.config.imageCount)") {
                    Slider(
                        value: Binding(
                            get: { Double(store.config.imageCount) },
                            set: { store.config.imageCount = Int($0) }
                        ),
                        in: 0...50, step: 1
                    )
                }

                Toggle("Spin slowly while moving", isOn: $store.config.imageSpin)

                Divider().padding(.vertical, 4)

                groupTitle("Trigger")

                labeled("Lock hotkey") {
                    HStack(spacing: 8) {
                        HotkeyRecorderView(combo: $store.config.lockHotkey)
                            .frame(width: 220, height: 28)
                        Button("Reset") {
                            store.config.lockHotkey = defaultLockHotkey
                        }
                    }
                }

                Divider().padding(.vertical, 4)

                Button(action: onLockNow) {
                    HStack {
                        Image(systemName: "lock.fill")
                        Text("Lock now").bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [.command])

                Text("Quit from the 🐌 menu in the menu bar.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(24)
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 540)
        .onChange(of: store.config) { _ in store.scheduleSave() }
    }

    private func groupTitle(_ s: String) -> some View {
        Text(s).font(.headline)
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .gif, .png, .jpeg]
        panel.begin { result in
            if result == .OK, let url = panel.url {
                store.config.imagePath = url.path
            }
        }
    }

    @ViewBuilder
    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
            content()
        }
    }
}

// MARK: - Settings window plumbing

final class SettingsWindowController {
    var window: NSWindow?

    func show<Root: View>(rootView: Root) {
        if window == nil {
            let hosting = NSHostingController(rootView: rootView)
            let w = NSWindow(contentViewController: hosting)
            w.title = "Snail Lock"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.setContentSize(NSSize(width: 520, height: 600))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        } else if let hosting = window?.contentViewController as? NSHostingController<Root> {
            hosting.rootView = rootView
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Menu bar

final class MenuActions: NSObject {
    let lockNowHandler: () -> Void
    let openSettingsHandler: () -> Void
    init(lockNow: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.lockNowHandler = lockNow
        self.openSettingsHandler = openSettings
    }
    @objc func lockNow()      { lockNowHandler() }
    @objc func openSettings() { openSettingsHandler() }
}

final class MenuBarController {
    let item: NSStatusItem
    let actions: MenuActions

    init(onLockNow: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        actions = MenuActions(lockNow: onLockNow, openSettings: onOpenSettings)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🐌"

        let menu = NSMenu()

        let lockItem = NSMenuItem(title: "Lock now", action: #selector(MenuActions.lockNow), keyEquivalent: "l")
        lockItem.keyEquivalentModifierMask = [.command, .shift]
        lockItem.target = actions
        menu.addItem(lockItem)

        let settingsItem = NSMenuItem(title: "Open settings…", action: #selector(MenuActions.openSettings), keyEquivalent: ",")
        settingsItem.target = actions
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Snail Lock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        item.menu = menu
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ConfigStore()
    let lockController = LockController()
    let hotkeyManager = HotkeyManager()
    var menuBar: MenuBarController?
    let settingsWindow = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()

        menuBar = MenuBarController(
            onLockNow: { [weak self] in self?.lockController.present() },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )

        registerHotkey(store.config.lockHotkey)

        store.onChange = { [weak self] cfg in
            self?.registerHotkey(cfg.lockHotkey)
        }

        openSettings()
    }

    func openSettings() {
        settingsWindow.show(rootView: SettingsView(
            store: store,
            onLockNow: { [weak self] in
                self?.settingsWindow.window?.orderOut(nil)
                self?.lockController.present()
            }
        ))
    }

    func registerHotkey(_ combo: String) {
        let trigger: () -> Void = { [weak self] in
            guard let self = self, !self.lockController.isLocked else { return }
            self.lockController.present()
        }
        if !hotkeyManager.register(combo, onTrigger: trigger) {
            // fall back to default
            _ = hotkeyManager.register(defaultLockHotkey, onTrigger: trigger)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Without a main menu, key equivalents like ⌘V / ⌘C don't route to focused text
    /// fields in accessory apps. Building a tiny App + Edit menu fixes that and also
    /// gives us a menu entry for the system emoji palette (⌃⌘Space).
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Hide Snail Lock", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Snail Lock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo",   action: Selector(("undo:")),  keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut",        action: #selector(NSText.cut(_:)),         keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy",       action: #selector(NSText.copy(_:)),        keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste",      action: #selector(NSText.paste(_:)),       keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a"))
        editMenu.addItem(.separator())
        let emoji = NSMenuItem(title: "Emoji & Symbols", action: #selector(NSApplication.orderFrontCharacterPalette(_:)), keyEquivalent: " ")
        emoji.keyEquivalentModifierMask = [.command, .control]
        editMenu.addItem(emoji)
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
