#!/usr/bin/env swift

import Cocoa
import ApplicationServices

// MARK: - Config model

struct Config: Codable {
    // AppConfig / apps are disabled along with the blocklist feature.
    // config.json may still contain an "apps" key — JSONDecoder ignores it.
    // To re-enable, uncomment these and the // MARK: - Blocklist section.
    //
    // struct AppConfig: Codable {
    //     var blocklist: [String]?
    // }
    struct Rule: Codable {
        var apps: [String]
        var key: String
        var modifiers: [String]?
        var notModifiers: [String]?
        var send: String
    }
    // var apps: [String: AppConfig]?
    var rules: [Rule]
}

// MARK: - Key code mapping

let keyCodeMap: [String: UInt16] = [
    "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
    "up": 126, "down": 125, "left": 123, "right": 124,
    "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118,
    "f5": 96, "f6": 97, "f7": 98, "f8": 100,
    "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
    "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
    "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
    "9": 25, "7": 26, "8": 28, "0": 29,
    "o": 31, "u": 32, "i": 34, "p": 35,
    "l": 37, "j": 38, "k": 40,
    "n": 45, "m": 46,
    ".": 47, "/": 44, ";": 41, "'": 39, ",": 43,
    "-": 27, "=": 24, "[": 33, "]": 30, "\\": 42, "`": 50,
]

let modifierMap: [String: CGEventFlags] = [
    "shift": .maskShift,
    "ctrl": .maskControl,
    "alt": .maskAlternate,
    "cmd": .maskCommand,
    "option": .maskAlternate,
    "control": .maskControl,
    "command": .maskCommand,
]

// MARK: - Global state

struct ConfigSnapshot {
    let config: Config
    let rules: [CompiledRule]
}
var snapshot: ConfigSnapshot?
let stateLock = NSLock()

// MARK: - Frontmost app cache
var cachedFrontmost: (bundleID: String, pid: Int32, expires: CFAbsoluteTime)?
let frontmostCacheDuration: CFAbsoluteTime = 0.15

struct CompiledRule {
    let apps: [String]
    let keyCode: UInt16
    let modifiers: CGEventFlags
    let notModifiers: CGEventFlags
    let send: String
}

// MARK: - Config loading

func configPath() -> String {
    if CommandLine.arguments.count > 1 { return CommandLine.arguments[1] }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return home + "/.config/key-remap/config.json"
}

func loadConfig(path: String) -> Config? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let config = try? JSONDecoder().decode(Config.self, from: data)
    else {
        fputs("Error: failed to load config from \(path)\n", stderr)
        return nil
    }
    return config
}

func compileRules(_ rules: [Config.Rule]) -> (compiled: [CompiledRule], warnings: [String]) {
    var compiled: [CompiledRule] = []
    var warnings: [String] = []

    for rule in rules {
        if rule.apps.isEmpty {
            warnings.append("rule for key '\(rule.key)' has empty apps, rule skipped")
            continue
        }
        guard let keyCode = keyCodeMap[rule.key.lowercased()] else {
            warnings.append("unknown key '\(rule.key)', rule skipped")
            continue
        }
        var modifiers: CGEventFlags = []
        var valid = true
        for m in rule.modifiers ?? [] {
            guard let flag = modifierMap[m.lowercased()] else {
                warnings.append("unknown modifier '\(m)' for key '\(rule.key)', rule skipped")
                valid = false
                break
            }
            modifiers.insert(flag)
        }
        guard valid else { continue }
        var notModifiers: CGEventFlags = []
        for m in rule.notModifiers ?? [] {
            guard let flag = modifierMap[m.lowercased()] else {
                warnings.append("unknown notModifier '\(m)' for key '\(rule.key)', rule skipped")
                valid = false
                break
            }
            notModifiers.insert(flag)
        }
        guard valid else { continue }
        let overlap = modifiers.intersection(notModifiers)
        if !overlap.isEmpty {
            warnings.append("modifier conflict for key '\(rule.key)', rule skipped")
            continue
        }
        compiled.append(CompiledRule(
            apps: rule.apps, keyCode: keyCode,
            modifiers: modifiers, notModifiers: notModifiers,
            send: rule.send
        ))
    }
    return (compiled, warnings)
}

// MARK: - Blocklist

// Blocklist support is disabled: not needed (vim/less are rarely used) and it
// caused latency — isBlocked() ran a synchronous `ps` scan on every key press.
// To re-enable, uncomment the code below, uncomment the isBlocked() call in the
// tap callback, and uncomment `blCache.removeAll()` in reloadConfig().
//
// var blCache: [Int32: (expires: CFAbsoluteTime, blocked: Bool)] = [:]
// let blCacheDuration: CFAbsoluteTime = 0.3
//
// func isBlocked(bundleID: String, pid: Int32, config: Config) -> Bool {
//     guard let appCfg = config.apps?[bundleID],
//           let blocklist = appCfg.blocklist, !blocklist.isEmpty
//     else { return false }
//
//     let now = CFAbsoluteTimeGetCurrent()
//     stateLock.lock()
//     if let cached = blCache[pid], cached.expires > now {
//         let blocked = cached.blocked
//         stateLock.unlock()
//         return blocked
//     }
//     stateLock.unlock()
//
//     let blockSet = Set(blocklist)
//     let t = Process()
//     t.executableURL = URL(fileURLWithPath: "/bin/ps")
//     t.arguments = ["-eo", "pid,ppid,comm="]
//     let p = Pipe()
//     t.standardOutput = p
//     try? t.run(); t.waitUntilExit()
//     let r = (try? p.fileHandleForReading.readToEnd()).flatMap { String(data: $0, encoding: .utf8) } ?? ""
//     var children: [Int32: [Int32]] = [:]; var cmds: [Int32: String] = [:]
//     for line in r.split(separator: "\n") {
//         let parts = line.split(separator: " ", omittingEmptySubsequences: true)
//         guard parts.count >= 3, let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else { continue }
//         children[ppid, default: []].append(pid); cmds[pid] = String(parts[2])
//     }
//     var stack = [pid]
//     var blocked = false
//     while !stack.isEmpty {
//         let cur = stack.removeLast()
//         if let c = cmds[cur], blockSet.contains(c.lowercased()) {
//             blocked = true; break
//         }
//         if let kids = children[cur] { stack.append(contentsOf: kids) }
//     }
//     stateLock.lock()
//     blCache[pid] = (now + blCacheDuration, blocked)
//     stateLock.unlock()
//     return blocked
// }

// MARK: - Send text

// Marker set on injected events so the tap can recognize and pass them
// through without re-matching rules (prevents infinite self-trigger loops).
let injectedMark: Int64 = 0x4B524D50

func sendString(_ string: String) -> Bool {
    guard let src = CGEventSource(stateID: .hidSystemState) else { return false }
    var chars = Array(string.utf16)
    guard !chars.isEmpty else { return false }
    guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
          let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
    else { return false }
    // Only the keyDown event carries the text; the keyUp is a plain release.
    chars.withUnsafeMutableBufferPointer { buf in
        down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress!)
    }
    down.setIntegerValueField(.eventSourceUserData, value: injectedMark)
    up.setIntegerValueField(.eventSourceUserData, value: injectedMark)
    down.post(tap: .cgAnnotatedSessionEventTap)
    up.post(tap: .cgAnnotatedSessionEventTap)
    return true
}

// MARK: - Reload

@discardableResult
func reloadConfig() -> Bool {
    let path = configPath()
    guard let newConfig = loadConfig(path: path) else {
        fputs("Error: reload failed, keeping previous config\n", stderr)
        return false
    }
    let (compiled, warnings) = compileRules(newConfig.rules)
    for w in warnings {
        fputs("Warning: \(w)\n", stderr)
    }
    if !newConfig.rules.isEmpty && compiled.isEmpty {
        fputs("Error: no valid rules remain, keeping previous config\n", stderr)
        return false
    }
    let s = ConfigSnapshot(config: newConfig, rules: compiled)
    stateLock.lock()
    snapshot = s
    // blCache.removeAll()  // blocklist disabled
    stateLock.unlock()
    return true
}

// MARK: - Frontmost app lookup

func frontmostInfo() -> (bundleID: String, pid: Int32)? {
    let now = CFAbsoluteTimeGetCurrent()
    stateLock.lock()
    if let c = cachedFrontmost, c.expires > now {
        let result = (c.bundleID, c.pid)
        stateLock.unlock()
        return result
    }
    stateLock.unlock()
    guard let app = NSWorkspace.shared.frontmostApplication,
          let bundleID = app.bundleIdentifier
    else { return nil }
    stateLock.lock()
    cachedFrontmost = (bundleID, app.processIdentifier, now + frontmostCacheDuration)
    stateLock.unlock()
    return (bundleID, app.processIdentifier)
}

// MARK: - Tap callback

let tapCallback: CGEventTapCallBack = { _, type, event, _ in
    guard type == .keyDown else { return Unmanaged.passUnretained(event) }

    // Pass through events this daemon injected, so a rule can never
    // re-trigger itself into an infinite loop.
    if event.getIntegerValueField(.eventSourceUserData) == injectedMark {
        return Unmanaged.passUnretained(event)
    }

    guard let front = frontmostInfo()
    else { return Unmanaged.passUnretained(event) }

    let kc = event.getIntegerValueField(.keyboardEventKeycode)
    let fl = event.flags

    stateLock.lock()
    let snap = snapshot
    stateLock.unlock()
    guard let snap = snap else { return Unmanaged.passUnretained(event) }

    for rule in snap.rules {
        guard rule.apps.contains(front.bundleID) else { continue }
        guard kc == numericCast(rule.keyCode) else { continue }
        guard fl.contains(rule.modifiers) else { continue }
        if rule.notModifiers.rawValue != 0,
           fl.rawValue & rule.notModifiers.rawValue != 0 {
            continue
        }
        // Blocklist check disabled — see // MARK: - Blocklist above.
        // 38 = kCGEventTargetUnixProcessID, PID of the process receiving the event
        // let targetField = CGEventField(rawValue: 38)!
        // let targetPid = Int32(event.getIntegerValueField(targetField))
        // let rootPID = targetPid > 0 ? targetPid : front.pid
        // if isBlocked(bundleID: front.bundleID, pid: rootPID, config: snap.config) {
        //     return Unmanaged.passUnretained(event)
        // }
        if !sendString(rule.send) {
            return Unmanaged.passUnretained(event)
        }
        return nil
    }

    return Unmanaged.passUnretained(event)
}

// MARK: - Main

if CommandLine.arguments.contains("--check-permission") {
    exit(AXIsProcessTrusted() ? 0 : 1)
}

if !AXIsProcessTrusted() {
    let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(opts)
    var waited = 0
    while !AXIsProcessTrusted() && waited < 15 { sleep(1); waited += 1 }
    if !AXIsProcessTrusted() {
        fputs("Error: accessibility permission denied\n", stderr)
        exit(1)
    }
}

let lockFD = open("/tmp/key-remap.lock", O_CREAT | O_RDWR, 0o644)
if lockFD == -1 {
    fputs("Error: cannot open lock file\n", stderr)
    exit(1)
}
if flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    fputs("key-remap already running\n", stderr)
    exit(0)
}

reloadConfig()
guard snapshot != nil else { exit(1) }

let eventMask = (1 << CGEventType.keyDown.rawValue)

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
    eventsOfInterest: CGEventMask(eventMask),
    callback: tapCallback, userInfo: nil
) else {
    fputs("Error: failed to create event tap (try re-granting accessibility permission)\n", stderr)
    exit(1)
}

// Invalidate the frontmost cache immediately when the app switches (timeout fallback)
let fgObserver = NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification,
    object: nil, queue: .main
) { _ in
    stateLock.lock()
    cachedFrontmost = nil
    stateLock.unlock()
}
_ = fgObserver

// SIGHUP reload
let sigSource = DispatchSource.makeSignalSource(signal: SIGHUP, queue: .main)
sigSource.setEventHandler { reloadConfig() }
sigSource.activate()
signal(SIGHUP, SIG_IGN)
signal(SIGINT) { _ in exit(0) }
signal(SIGTERM) { _ in exit(0) }

CFRunLoopAddSource(CFRunLoopGetCurrent(),
    CFMachPortCreateRunLoopSource(nil, tap, 0), .defaultMode)
CGEvent.tapEnable(tap: tap, enable: true)
CFRunLoopRun()
