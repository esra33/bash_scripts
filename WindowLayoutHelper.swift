// WindowLayoutHelper: captures and restores window frames across displays and desktops.
// Compiled on demand by WindowLayouts.sh. Needs Accessibility permission for the terminal app.
//
//   WindowLayoutHelper save                      prints the current layout as JSON
//   WindowLayoutHelper apply <file> [--dry-run] [--launch] [--move-desktops]
//   WindowLayoutHelper desktops                  lists desktops and their "Switch to Desktop N" shortcuts
//   WindowLayoutHelper switch <n>                shows Desktop n using its shortcut
//   WindowLayoutHelper check                     verifies (and prompts for) Accessibility access

import AppKit
import ApplicationServices
import Foundation

//-------------------------------------------------------
// Private SPI (read-only space queries + AX <-> CGWindowID bridging)

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> Int32

@_silgen_name("CGSCopySpacesForWindows")
func CGSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ windowIDs: CFArray) -> Unmanaged<CFArray>?

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> Unmanaged<CFArray>?

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

@_silgen_name("_AXUIElementCreateWithRemoteToken")
func _AXUIElementCreateWithRemoteToken(_ token: CFData) -> Unmanaged<AXUIElement>?

//-------------------------------------------------------
// Profile model

struct Rect: Codable {
	var x: Double, y: Double, w: Double, h: Double
	init(_ r: CGRect) { x = r.origin.x; y = r.origin.y; w = r.size.width; h = r.size.height }
	var cg: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}

struct DisplayInfo: Codable {
	var uuid: String
	var name: String
	var isMain: Bool
	var frame: Rect
	var desktops: Int
}

struct WindowInfo: Codable {
	var app: String
	var bundleId: String?
	var windowId: UInt32?
	var title: String
	var display: String?
	var desktop: Int?          // 1-based desktop index on its display; nil = all desktops / unknown
	var fullscreen: Bool
	var minimized: Bool
	var frame: Rect            // absolute, global top-left coordinates
	var relativeFrame: Rect    // relative to the display's origin
}

struct Profile: Codable {
	var version: Int
	var savedAt: String
	var displays: [DisplayInfo]
	var windows: [WindowInfo]
}

//-------------------------------------------------------
// Displays and spaces

struct LiveDisplay {
	let id: CGDirectDisplayID
	let uuid: String
	let name: String
	let isMain: Bool
	let frame: CGRect
}

struct SpaceLocation {
	let displayUUID: String
	let desktop: Int?          // nil for fullscreen spaces
	let fullscreen: Bool
}

func liveDisplays() -> [LiveDisplay] {
	var count: UInt32 = 0
	CGGetActiveDisplayList(0, nil, &count)
	var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
	CGGetActiveDisplayList(count, &ids, &count)

	var names = [CGDirectDisplayID: String]()
	for screen in NSScreen.screens {
		if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
			names[number.uint32Value] = screen.localizedName
		}
	}

	return ids.compactMap { id in
		guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
		      let uuid = CFUUIDCreateString(nil, cfUUID) as String? else { return nil }
		return LiveDisplay(id: id, uuid: uuid, name: names[id] ?? "Display \(id)",
		                   isMain: CGDisplayIsMain(id) != 0, frame: CGDisplayBounds(id))
	}
}

// Maps every space id to the display it belongs to and its desktop number on that display.
func spaceMap(displays: [LiveDisplay]) -> (spaces: [UInt64: SpaceLocation], desktopCounts: [String: Int]) {
	var spaces = [UInt64: SpaceLocation]()
	var counts = [String: Int]()
	let mainUUID = displays.first(where: { $0.isMain })?.uuid ?? displays.first?.uuid ?? "Main"
	guard let managed = CGSCopyManagedDisplaySpaces(CGSMainConnectionID())?.takeRetainedValue() as? [[String: Any]] else {
		return (spaces, counts)
	}

	for display in managed {
		var uuid = display["Display Identifier"] as? String ?? "Main"
		// "Main" shows up when "Displays have separate Spaces" is off.
		if uuid == "Main" { uuid = mainUUID }
		var desktop = 0
		for space in display["Spaces"] as? [[String: Any]] ?? [] {
			guard let id = (space["ManagedSpaceID"] as? NSNumber)?.uint64Value else { continue }
			let fullscreen = (space["type"] as? NSNumber)?.intValue == 4
			if !fullscreen { desktop += 1 }
			spaces[id] = SpaceLocation(displayUUID: uuid, desktop: fullscreen ? nil : desktop, fullscreen: fullscreen)
		}
		counts[uuid] = desktop
	}
	return (spaces, counts)
}

func spaceIds(for windowId: CGWindowID) -> [UInt64] {
	let ids = [NSNumber(value: windowId)] as CFArray
	guard let spaces = CGSCopySpacesForWindows(CGSMainConnectionID(), 0x7, ids)?.takeRetainedValue() as? [NSNumber] else {
		return []
	}
	return spaces.map { $0.uint64Value }
}

func desktopSpaceId(display: String, desktop: Int) -> UInt64? {
	guard let managed = CGSCopyManagedDisplaySpaces(CGSMainConnectionID())?.takeRetainedValue() as? [[String: Any]] else {
		return nil
	}
	let displays = liveDisplays()
	let mainUUID = displays.first(where: { $0.isMain })?.uuid ?? "Main"
	for entry in managed {
		var uuid = entry["Display Identifier"] as? String ?? "Main"
		if uuid == "Main" { uuid = mainUUID }
		guard uuid == display else { continue }
		let desktops = (entry["Spaces"] as? [[String: Any]] ?? []).filter { ($0["type"] as? NSNumber)?.intValue != 4 }
		guard desktop >= 1, desktop <= desktops.count else { return nil }
		return (desktops[desktop - 1]["ManagedSpaceID"] as? NSNumber)?.uint64Value
	}
	return nil
}

//-------------------------------------------------------
// Accessibility helpers

func axValue<T>(_ element: AXUIElement, _ attribute: String) -> T? {
	var value: CFTypeRef?
	guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
	return value as? T
}

func axFrame(_ element: AXUIElement) -> CGRect? {
	guard let posValue: AXValue = axValue(element, kAXPositionAttribute),
	      let sizeValue: AXValue = axValue(element, kAXSizeAttribute) else { return nil }
	var pos = CGPoint.zero, size = CGSize.zero
	AXValueGetValue(posValue, .cgPoint, &pos)
	AXValueGetValue(sizeValue, .cgSize, &size)
	return CGRect(origin: pos, size: size)
}

@discardableResult
func axSetFrame(_ element: AXUIElement, _ frame: CGRect) -> Bool {
	var pos = frame.origin, size = frame.size
	guard let posValue = AXValueCreate(.cgPoint, &pos), let sizeValue = AXValueCreate(.cgSize, &size) else { return false }
	// Position, size, position: moving to a smaller display can clamp the size if it is set first.
	let a = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posValue)
	let b = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
	let c = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posValue)
	return a == .success || b == .success || c == .success
}

func axSetBool(_ element: AXUIElement, _ attribute: String, _ value: Bool) {
	AXUIElementSetAttributeValue(element, attribute as CFString, (value ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef)
}

func windowId(of element: AXUIElement) -> CGWindowID? {
	var id: CGWindowID = 0
	return _AXUIElementGetWindow(element, &id) == .success && id != 0 ? id : nil
}

func isStandardWindow(_ element: AXUIElement) -> Bool {
	(axValue(element, kAXSubroleAttribute) as String?) == (kAXStandardWindowSubrole as String)
}

// kAXWindowsAttribute only returns windows on the visible desktops. Windows on other
// desktops are reachable by building AX elements from remote tokens (same trick AltTab uses).
func windowsByBruteForce(pid: pid_t, wanted: Set<CGWindowID>) -> [AXUIElement] {
	var token = Data(count: 20)
	token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
	token.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
	token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f636f)) { Data($0) })

	var found = [AXUIElement]()
	var remaining = wanted
	for elementId: UInt64 in 0..<1000 where !remaining.isEmpty {
		token.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementId) { Data($0) })
		guard let element = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue(),
		      isStandardWindow(element),
		      let id = windowId(of: element), remaining.contains(id) else { continue }
		remaining.remove(id)
		found.append(element)
	}
	return found
}

// Layer-0 windows that live on a desktop (visible or not), grouped by owning pid.
// Skips hidden helper windows, and needs no Screen Recording permission.
func cgWindowIdsByPid(knownSpaces: Set<UInt64>) -> [pid_t: Set<CGWindowID>] {
	guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
		return [:]
	}
	var result = [pid_t: Set<CGWindowID>]()
	for info in list {
		guard (info[kCGWindowLayer as String] as? Int) == 0,
		      let pid = info[kCGWindowOwnerPID as String] as? pid_t,
		      let id = info[kCGWindowNumber as String] as? CGWindowID,
		      let bounds = info[kCGWindowBounds as String] as? [String: Any],
		      let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
		      rect.width > 50, rect.height > 50,
		      !knownSpaces.isDisjoint(with: spaceIds(for: id)) else { continue }
		result[pid, default: []].insert(id)
	}
	return result
}

struct LiveWindow {
	let element: AXUIElement
	let app: NSRunningApplication
	let id: CGWindowID?
	let title: String
}

func liveWindows() -> [LiveWindow] {
	let cgIds = cgWindowIdsByPid(knownSpaces: Set(spaceMap(displays: liveDisplays()).spaces.keys))
	var result = [LiveWindow]()

	for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
		let appElement = AXUIElementCreateApplication(app.processIdentifier)
		AXUIElementSetMessagingTimeout(appElement, 1.0)

		var elements = (axValue(appElement, kAXWindowsAttribute) as [AXUIElement]?) ?? []
		elements = elements.filter(isStandardWindow)
		let seen = Set(elements.compactMap(windowId))
		let missing = (cgIds[app.processIdentifier] ?? []).subtracting(seen)
		if !missing.isEmpty {
			elements += windowsByBruteForce(pid: app.processIdentifier, wanted: missing)
		}

		for element in elements {
			result.append(LiveWindow(element: element, app: app, id: windowId(of: element),
			                         title: axValue(element, kAXTitleAttribute) ?? ""))
		}
	}
	return result
}

//-------------------------------------------------------
// Commands

func fail(_ message: String) -> Never {
	FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
	exit(1)
}

func requireAccessibility(prompt: Bool) {
	let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
	if !AXIsProcessTrustedWithOptions(options) {
		fail("Accessibility access is missing. Enable your terminal app in System Settings > Privacy & Security > Accessibility, then restart it.")
	}
}

func save() {
	let displays = liveDisplays()
	let (spaces, desktopCounts) = spaceMap(displays: displays)
	var windows = [WindowInfo]()

	for live in liveWindows() {
		guard let frame = axFrame(live.element) else { continue }
		let minimized: Bool = axValue(live.element, kAXMinimizedAttribute) ?? false
		let fullscreen: Bool = axValue(live.element, "AXFullScreen") ?? false

		var displayUUID: String?
		var desktop: Int?
		var onFullscreenSpace = false
		if let id = live.id {
			let ids = spaceIds(for: id)
			// A window on several spaces is assigned to "all desktops": keep display, drop desktop.
			if let first = ids.first, let location = spaces[first] {
				displayUUID = location.displayUUID
				desktop = ids.count == 1 ? location.desktop : nil
				onFullscreenSpace = location.fullscreen
			}
		}
		if displayUUID == nil {
			displayUUID = displays.max(by: {
				$0.frame.intersection(frame).width * $0.frame.intersection(frame).height <
				$1.frame.intersection(frame).width * $1.frame.intersection(frame).height
			})?.uuid
		}

		let origin = displays.first(where: { $0.uuid == displayUUID })?.frame.origin ?? .zero
		windows.append(WindowInfo(
			app: live.app.localizedName ?? "Unknown",
			bundleId: live.app.bundleIdentifier,
			windowId: live.id,
			title: live.title,
			display: displayUUID,
			desktop: desktop,
			fullscreen: fullscreen || onFullscreenSpace,
			minimized: minimized,
			frame: Rect(frame),
			relativeFrame: Rect(frame.offsetBy(dx: -origin.x, dy: -origin.y))))
	}

	let profile = Profile(
		version: 1,
		savedAt: ISO8601DateFormatter().string(from: Date()),
		displays: displays.map {
			DisplayInfo(uuid: $0.uuid, name: $0.name, isMain: $0.isMain, frame: Rect($0.frame),
			            desktops: desktopCounts[$0.uuid] ?? 1)
		},
		windows: windows)

	let encoder = JSONEncoder()
	encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
	print(String(data: try! encoder.encode(profile), encoding: .utf8)!)
}

// Matches saved windows to live ones: exact window id + title, then title, then order within the app.
func match(saved: [WindowInfo], live: [LiveWindow]) -> [(WindowInfo, LiveWindow?)] {
	var claimed = Set<Int>()
	var pairs = [LiveWindow?](repeating: nil, count: saved.count)
	let candidates: (WindowInfo) -> [Int] = { window in
		live.indices.filter { live[$0].app.bundleIdentifier == window.bundleId && !claimed.contains($0) }
	}
	let passes: [(WindowInfo, LiveWindow) -> Bool] = [
		{ s, l in s.windowId != nil && s.windowId == l.id && s.title == l.title },
		{ s, l in !s.title.isEmpty && s.title == l.title },
		{ _, _ in true },
	]
	for pass in passes {
		for (i, window) in saved.enumerated() where pairs[i] == nil {
			if let index = candidates(window).first(where: { pass(window, live[$0]) }) {
				claimed.insert(index)
				pairs[i] = live[index]
			}
		}
	}
	return zip(saved, pairs).map { ($0, $1) }
}

// Picks the live display for a saved one: same UUID, then same name, then main.
func resolveDisplay(_ uuid: String?, profile: Profile, displays: [LiveDisplay]) -> LiveDisplay? {
	if let exact = displays.first(where: { $0.uuid == uuid }) { return exact }
	if let saved = profile.displays.first(where: { $0.uuid == uuid }),
	   let byName = displays.first(where: { $0.name == saved.name }) { return byName }
	return displays.first(where: { $0.isMain }) ?? displays.first
}

//-------------------------------------------------------
// Moving windows between desktops without yabai. Accessibility can still move a window onto another
// display, where it lands on the desktop that display is showing, and the "Switch to Desktop N"
// shortcuts pick which desktop that is. A move within one display bounces off a second display.
// (Holding the title bar while switching desktops, Amethyst's trick, does not work with synthetic
// mouse events on macOS 26.)

struct Desktop {
	let spaceId: UInt64
	let display: String
	let number: Int            // 1-based on its display
	let globalNumber: Int      // 1-based across all displays, as used by "Switch to Desktop N"
}

struct Hotkey {
	let keyCode: CGKeyCode
	let flags: CGEventFlags
}

// Desktops in Mission Control order, plus the space currently visible on each display.
func desktopList() -> (desktops: [Desktop], current: [String: UInt64]) {
	var desktops = [Desktop]()
	var current = [String: UInt64]()
	guard let managed = CGSCopyManagedDisplaySpaces(CGSMainConnectionID())?.takeRetainedValue() as? [[String: Any]] else {
		return (desktops, current)
	}
	let displays = liveDisplays()
	let mainUUID = displays.first(where: { $0.isMain })?.uuid ?? "Main"
	for entry in managed {
		var uuid = entry["Display Identifier"] as? String ?? "Main"
		if uuid == "Main" { uuid = mainUUID }
		if let id = ((entry["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? NSNumber)?.uint64Value {
			current[uuid] = id
		}
		var number = 0
		for space in entry["Spaces"] as? [[String: Any]] ?? [] where (space["type"] as? NSNumber)?.intValue != 4 {
			guard let id = (space["ManagedSpaceID"] as? NSNumber)?.uint64Value else { continue }
			number += 1
			desktops.append(Desktop(spaceId: id, display: uuid, number: number, globalNumber: desktops.count + 1))
		}
	}
	return (desktops, current)
}

// Enabled "Switch to Desktop N" shortcuts (System Settings > Keyboard > Keyboard Shortcuts > Mission Control),
// keyed by N. They are symbolic hot keys 118 (Desktop 1) through 133 (Desktop 16).
func desktopHotkeys() -> [Int: Hotkey] {
	let domain = "com.apple.symbolichotkeys" as CFString
	CFPreferencesAppSynchronize(domain)
	guard let all = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any] else { return [:] }
	var result = [Int: Hotkey]()
	for n in 1...16 {
		guard let entry = all[String(117 + n)] as? [String: Any],
		      (entry["enabled"] as? NSNumber)?.boolValue == true,
		      let params = (entry["value"] as? [String: Any])?["parameters"] as? [NSNumber], params.count == 3 else { continue }
		// The modifier mask uses the same bits as CGEventFlags.
		result[n] = Hotkey(keyCode: CGKeyCode(params[1].intValue), flags: CGEventFlags(rawValue: params[2].uint64Value))
	}
	return result
}

func currentSpace(on display: String) -> UInt64? {
	desktopList().current[display]
}

func waitForSpace(_ spaceId: UInt64, on display: String, timeout: TimeInterval = 2) -> Bool {
	let deadline = Date().addingTimeInterval(timeout)
	while Date() < deadline {
		if currentSpace(on: display) == spaceId {
			Thread.sleep(forTimeInterval: 0.4)   // let the slide animation finish
			return true
		}
		Thread.sleep(forTimeInterval: 0.05)
	}
	return false
}

func press(_ hotkey: Hotkey) {
	let source = CGEventSource(stateID: .hidSystemState)
	for keyDown in [true, false] {
		let event = CGEvent(keyboardEventSource: source, virtualKey: hotkey.keyCode, keyDown: keyDown)
		event?.flags = hotkey.flags
		event?.post(tap: .cghidEventTap)
	}
}

// Shows a desktop on its display. Succeeds right away if it is already showing.
func switchTo(_ desktop: Desktop, hotkeys: [Int: Hotkey]) -> Bool {
	if currentSpace(on: desktop.display) == desktop.spaceId { return true }
	guard let hotkey = hotkeys[desktop.globalNumber] else { return false }
	press(hotkey)
	return waitForSpace(desktop.spaceId, on: desktop.display)
}

// A frame for parking a window on another display while its own display switches desktops.
func parkingFrame(_ frame: CGRect, on display: LiveDisplay) -> CGRect {
	let size = CGSize(width: min(frame.width, display.frame.width), height: min(frame.height, display.frame.height))
	return CGRect(origin: CGPoint(x: display.frame.midX - size.width / 2, y: display.frame.midY - size.height / 2), size: size)
}

struct DesktopMove {
	let label: String
	let live: LiveWindow
	let target: Desktop
	let frame: CGRect
	let minimize: Bool
	let where_: String
}

// Moves each window to its saved desktop. Returns the ones that could not be moved, with the reason.
func moveAcrossDesktops(_ moves: [DesktopMove]) -> [String] {
	let hotkeys = desktopHotkeys()
	let (desktops, startSpaces) = desktopList()
	let displays = liveDisplays()
	var failed = [String]()

	for move in moves {
		guard let id = move.live.id else { failed.append("\(move.label) (no window id)"); continue }
		let onTarget = { spaceIds(for: id).contains(move.target.spaceId) }
		guard hotkeys[move.target.globalNumber] != nil else {
			failed.append("\(move.label) (no shortcut for Desktop \(move.target.globalNumber))")
			continue
		}
		// A window on a desktop that is not showing cannot be moved, so show it first.
		guard let source = desktops.first(where: { spaceIds(for: id).contains($0.spaceId) }),
		      switchTo(source, hotkeys: hotkeys) else {
			failed.append("\(move.label) (could not show its current desktop)")
			continue
		}
		if source.display == move.target.display {
			guard let parking = displays.first(where: { $0.uuid != move.target.display }) else {
				failed.append("\(move.label) (moving within a display needs a second display)")
				continue
			}
			axSetFrame(move.live.element, parkingFrame(move.frame, on: parking))
			Thread.sleep(forTimeInterval: 0.2)
		}
		guard switchTo(move.target, hotkeys: hotkeys) else {
			failed.append("\(move.label) (Desktop \(move.target.globalNumber) did not come up)")
			continue
		}
		axSetFrame(move.live.element, move.frame)
		Thread.sleep(forTimeInterval: 0.2)

		if onTarget() {
			if move.minimize { axSetBool(move.live.element, kAXMinimizedAttribute, true) }
			print("  moved     \(move.label) -> \(move.where_)")
		} else {
			failed.append("\(move.label) (did not land on \(move.where_))")
		}
	}

	// Put every display back on the desktop it was showing.
	for (display, spaceId) in startSpaces {
		if let desktop = desktops.first(where: { $0.spaceId == spaceId && $0.display == display }) {
			_ = switchTo(desktop, hotkeys: hotkeys)
		}
	}
	return failed
}

func printDesktops() {
	let hotkeys = desktopHotkeys()
	let (desktops, current) = desktopList()
	let names = Dictionary(liveDisplays().map { ($0.uuid, $0.name) }, uniquingKeysWith: { a, _ in a })
	for desktop in desktops {
		let shortcut = hotkeys[desktop.globalNumber] == nil ? "no shortcut" : "shortcut on"
		let showing = current[desktop.display] == desktop.spaceId ? "  (showing)" : ""
		print("Desktop \(desktop.globalNumber): \(names[desktop.display] ?? desktop.display) desktop \(desktop.number), \(shortcut)\(showing)")
	}
}

func yabaiPath() -> String? {
	for path in ["/opt/homebrew/bin/yabai", "/usr/local/bin/yabai"] where FileManager.default.isExecutableFile(atPath: path) {
		return path
	}
	return nil
}

func run(_ path: String, _ args: [String]) -> (status: Int32, output: Data) {
	let process = Process()
	let pipe = Pipe()
	process.executableURL = URL(fileURLWithPath: path)
	process.arguments = args
	process.standardOutput = pipe
	process.standardError = Pipe()
	do { try process.run() } catch { return (-1, Data()) }
	let data = pipe.fileHandleForReading.readDataToEndOfFile()
	process.waitUntilExit()
	return (process.terminationStatus, data)
}

func yabaiMove(_ yabai: String, windowId: CGWindowID, toSpace spaceId: UInt64) -> Bool {
	let query = run(yabai, ["-m", "query", "--spaces"])
	guard query.status == 0,
	      let spaces = try? JSONSerialization.jsonObject(with: query.output) as? [[String: Any]],
	      let index = spaces.first(where: { ($0["id"] as? NSNumber)?.uint64Value == spaceId })?["index"] as? Int else {
		return false
	}
	return run(yabai, ["-m", "window", String(windowId), "--space", String(index)]).status == 0
}

func launchMissingApps(_ profile: Profile) {
	let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
	let missing = Set(profile.windows.compactMap { $0.bundleId }).subtracting(running)
	guard !missing.isEmpty else { return }

	for bundleId in missing.sorted() {
		print("Launching \(bundleId)")
		_ = run("/usr/bin/open", ["-g", "-b", bundleId])
	}
	// Give the apps time to open their windows.
	let deadline = Date().addingTimeInterval(15)
	while Date() < deadline {
		let now = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
		if missing.isSubset(of: now) { break }
		Thread.sleep(forTimeInterval: 0.5)
	}
	Thread.sleep(forTimeInterval: 2)
}

func apply(path: String, dryRun: Bool, launch: Bool, moveDesktops: Bool) {
	guard let data = FileManager.default.contents(atPath: path) else { fail("Cannot read \(path)") }
	let profile: Profile
	do { profile = try JSONDecoder().decode(Profile.self, from: data) } catch { fail("Invalid layout file: \(error)") }

	if launch && !dryRun { launchMissingApps(profile) }

	let displays = liveDisplays()
	let (spaces, _) = spaceMap(displays: displays)
	let yabai = yabaiPath()
	var moved = 0, skipped = 0
	var wrongDesktop = [String]()
	var desktopMoves = [DesktopMove]()
	let desktops = desktopList().desktops

	for (saved, live) in match(saved: profile.windows, live: liveWindows()) {
		let label = "\(saved.app) - \(saved.title.isEmpty ? "(untitled)" : saved.title)"
		guard let live = live else {
			print("  missing   \(label)")
			skipped += 1
			continue
		}
		guard let display = resolveDisplay(saved.display, profile: profile, displays: displays) else { continue }

		// Fit the saved frame onto the (possibly different) target display.
		var frame = saved.relativeFrame.cg.offsetBy(dx: display.frame.origin.x, dy: display.frame.origin.y)
		frame.size.width = min(frame.width, display.frame.width)
		frame.size.height = min(frame.height, display.frame.height)
		frame.origin.x = max(display.frame.minX, min(frame.origin.x, display.frame.maxX - frame.width))
		frame.origin.y = max(display.frame.minY, min(frame.origin.y, display.frame.maxY - frame.height))

		let where_ = "\(display.name)\(saved.desktop.map { ", desktop \($0)" } ?? "")"
		if dryRun {
			print("  would move \(label) -> \(where_) \(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))")
			continue
		}

		let currentlyFullscreen: Bool = axValue(live.element, "AXFullScreen") ?? false
		if currentlyFullscreen && !saved.fullscreen {
			axSetBool(live.element, "AXFullScreen", false)
			Thread.sleep(forTimeInterval: 1)
		}
		if (axValue(live.element, kAXMinimizedAttribute) as Bool?) == true && !saved.minimized {
			axSetBool(live.element, kAXMinimizedAttribute, false)
		}

		// Desktop placement first, since moving spaces can change the frame.
		var deferMinimize = false
		if let desktop = saved.desktop, let id = live.id,
		   let target = desktopSpaceId(display: display.uuid, desktop: desktop),
		   !spaceIds(for: id).contains(target) {
			if let yabai = yabai, yabaiMove(yabai, windowId: id, toSpace: target) {
				Thread.sleep(forTimeInterval: 0.2)
			} else if moveDesktops, let targetDesktop = desktops.first(where: { $0.spaceId == target }) {
				// Done after every window is placed, since it switches desktops on screen.
				desktopMoves.append(DesktopMove(label: label, live: live, target: targetDesktop, frame: frame,
				                                minimize: saved.minimized, where_: where_))
				deferMinimize = true
			} else {
				let current = spaceIds(for: id).first.flatMap { spaces[$0]?.desktop }.map(String.init) ?? "?"
				wrongDesktop.append("\(label) (on desktop \(current), saved on \(where_))")
			}
		}

		if !saved.fullscreen {
			axSetFrame(live.element, frame)
		} else if !currentlyFullscreen {
			axSetFrame(live.element, frame)
			axSetBool(live.element, "AXFullScreen", true)
		}
		if saved.minimized && !deferMinimize { axSetBool(live.element, kAXMinimizedAttribute, true) }

		print("  placed    \(label) -> \(where_)")
		moved += 1
	}

	if !desktopMoves.isEmpty {
		print("Moving \(desktopMoves.count) window(s) to their desktops (the screen will switch desktops)...")
		wrongDesktop += moveAcrossDesktops(desktopMoves)
	}

	print("\(dryRun ? "Dry run" : "Placed \(moved) window(s)"), \(skipped) missing")
	if !wrongDesktop.isEmpty {
		print("\nThese windows are on a different desktop than saved. Use --move-desktops (needs the")
		print("\"Switch to Desktop N\" shortcuts), install yabai with its scripting addition, or drag them manually:")
		wrongDesktop.forEach { print("  \($0)") }
	}
}

//-------------------------------------------------------
// Entry point

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "check":
	requireAccessibility(prompt: true)
	print("Accessibility access OK")
case "save":
	requireAccessibility(prompt: true)
	save()
case "desktops":
	printDesktops()
case "switch":
	guard args.count >= 2, let n = Int(args[1]),
	      let desktop = desktopList().desktops.first(where: { $0.globalNumber == n }) else { fail("Usage: WindowLayoutHelper switch <desktop number>") }
	requireAccessibility(prompt: true)
	if !switchTo(desktop, hotkeys: desktopHotkeys()) { fail("Desktop \(n) did not come up; check its shortcut in System Settings") }
	print("Showing Desktop \(n)")
case "apply":
	guard args.count >= 2 else { fail("Usage: WindowLayoutHelper apply <file> [--dry-run] [--launch] [--move-desktops]") }
	requireAccessibility(prompt: true)
	apply(path: args[1], dryRun: args.contains("--dry-run"), launch: args.contains("--launch"),
	      moveDesktops: args.contains("--move-desktops"))
default:
	fail("Usage: WindowLayoutHelper save | apply <file> [--dry-run] [--launch] [--move-desktops] | desktops | switch <n> | check")
}
