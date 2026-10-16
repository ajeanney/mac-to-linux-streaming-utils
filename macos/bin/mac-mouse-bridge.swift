import CoreGraphics
import Foundation
import Network

if !CGPreflightPostEventAccess() {
    _ = CGRequestPostEventAccess()
    fputs("mac-mouse-bridge needs Accessibility permission in System Settings to post clicks and keys.\n", stderr)
}

let port = NWEndpoint.Port(rawValue: 45991)!
let queue = DispatchQueue(label: "com.mac-three-screens.mouse-bridge")
let sessionQueue = DispatchQueue(label: "com.mac-three-screens.session")
// Releases are quick and must never queue behind a slow prepare, so they get
// their own queue instead of sharing the session work.
let releaseQueue = DispatchQueue(label: "com.mac-three-screens.session-release")
var sessionBusy = false
var lastPoint = CGEvent(source: nil)?.location ?? CGPoint(x: 0, y: 0)
var pressedButtons = Set<Int>()
var clickCounts = [Int: Int]()
var lastClickTimes = [Int: TimeInterval]()
var lastClickPoints = [Int: CGPoint]()
var mouseModifierFlags: CGEventFlags = []
// Chromium validates a press/drag/release as one sequence against
// kCGMouseEventNumber. CoreGraphics leaves the field 0 even on a shared
// event source, so the drag never continues; Firefox does not check it.
var nextMouseEventNumber: Int64 = 1
var currentMouseEventNumber: Int64 = 0
let doubleClickInterval: TimeInterval = 0.5
let doubleClickDistance: CGFloat = 8
// One source for every synthetic event. Passing nil makes CoreGraphics mint a
// fresh source per event, which breaks kCGMouseEventNumber continuity; Chromium
// validates press/move/release against that sequence and silently drops drags.
let eventSource = CGEventSource(stateID: .hidSystemState)

func applyMouseModifierFlags(_ event: CGEvent) {
    // CGEventSource can carry unrelated state bits from the physical Mac
    // device. Keep only the modifier flags that are meaningful to the bridge.
    event.flags = []
    let systemFlags = CGEventSource.flagsState(.hidSystemState)
    for flag: CGEventFlags in [.maskCommand, .maskShift, .maskAlternate] {
        if systemFlags.contains(flag) {
            event.flags.insert(flag)
        }
    }
    event.flags.formUnion(mouseModifierFlags)
}

func postMove(_ x: CGFloat, _ y: CGFloat) {
    let point = CGPoint(x: x, y: y)
    lastPoint = point

    let dragType: CGEventType?
    let dragButton: CGMouseButton
    if pressedButtons.contains(1) {
        dragType = .leftMouseDragged
        dragButton = .left
    } else if pressedButtons.contains(3) {
        dragType = .rightMouseDragged
        dragButton = .right
    } else if pressedButtons.contains(2) {
        dragType = .otherMouseDragged
        dragButton = .center
    } else {
        dragType = nil
        dragButton = .left
    }

    // A drag must always report click state 1. Carrying the press's count
    // forward makes Chromium read a drag that starts after a double-click as
    // another double-click and abandon the drag.
    let activeClickCount = 1

    if let dragType,
       let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: dragType,
            mouseCursorPosition: point,
            mouseButton: dragButton
       ) {
        applyMouseModifierFlags(event)
        event.setIntegerValueField(.mouseEventClickState, value: Int64(activeClickCount))
        event.setIntegerValueField(.mouseEventNumber, value: currentMouseEventNumber)
        event.post(tap: .cgSessionEventTap)
        // No warp while dragging: the drag event already carries the position,
        // and a warp racing it cancels Chromium's drag session.
    } else if let event = CGEvent(
        mouseEventSource: eventSource,
        mouseType: .mouseMoved,
        mouseCursorPosition: point,
        mouseButton: .left
    ) {
        // Warping updates the cursor position; this event updates AppKit,
        // tracking areas, tooltips, and other hover state.
        applyMouseModifierFlags(event)
        event.post(tap: .cgSessionEventTap)
        CGWarpMouseCursorPosition(point)
    }
}

func postButton(_ button: Int, down: Bool) {
    if (button == 8 || button == 9) {
        let number = UInt32(button - 5) // Linux 8/9 -> macOS buttons 3/4
        let type: CGEventType = down ? .otherMouseDown : .otherMouseUp
        if let mouseButton = CGMouseButton(rawValue: number),
           let event = CGEvent(
                mouseEventSource: eventSource,
                mouseType: type,
                mouseCursorPosition: lastPoint,
                mouseButton: mouseButton
           ) {
            applyMouseModifierFlags(event)
            event.setIntegerValueField(.mouseEventClickState, value: down ? 1 : 0)
            event.post(tap: .cgSessionEventTap)
        }
        return
    }

    let mouseButton: CGMouseButton
    let eventType: CGEventType
    switch button {
    case 1:
        mouseButton = .left
        eventType = down ? .leftMouseDown : .leftMouseUp
    case 2:
        mouseButton = .center
        eventType = down ? .otherMouseDown : .otherMouseUp
    case 3:
        mouseButton = .right
        eventType = down ? .rightMouseDown : .rightMouseUp
    default:
        return
    }

    if down {
        let now = Date.timeIntervalSinceReferenceDate
        let previousTime = lastClickTimes[button] ?? 0
        let previousPoint = lastClickPoints[button] ?? lastPoint
        let isSecondClick = now - previousTime <= doubleClickInterval &&
            hypot(lastPoint.x - previousPoint.x, lastPoint.y - previousPoint.y) <= doubleClickDistance
        clickCounts[button] = isSecondClick ? 2 : 1
        lastClickTimes[button] = now
        lastClickPoints[button] = lastPoint
        pressedButtons.insert(button)
        if button == 1 {
            currentMouseEventNumber = nextMouseEventNumber
            nextMouseEventNumber += 1
        }
    } else {
        pressedButtons.remove(button)
    }

    let clickCount = clickCounts[button] ?? 1
    // A real mouse-up reports click state 0; carrying the press count forward
    // makes Chromium treat the release as part of the next click.
    let eventClickCount = down ? clickCount : 0

    if let event = CGEvent(
        mouseEventSource: eventSource,
        mouseType: eventType,
        mouseCursorPosition: lastPoint,
        mouseButton: mouseButton
    ) {
        applyMouseModifierFlags(event)
        event.setIntegerValueField(.mouseEventClickState, value: Int64(eventClickCount))
        event.setIntegerValueField(.mouseEventNumber, value: currentMouseEventNumber)
        event.post(tap: .cgSessionEventTap)
    }
    CGWarpMouseCursorPosition(lastPoint)
}

func setMouseModifier(_ modifier: String, down: Bool) {
    let flag: CGEventFlags
    switch modifier {
    case "shift":
        flag = .maskShift
    case "command":
        flag = .maskCommand
    case "control":
        flag = .maskControl
    default:
        return
    }
    if down {
        mouseModifierFlags.insert(flag)
    } else {
        mouseModifierFlags.remove(flag)
        if modifier == "shift" {
            releaseShift()
        } else if modifier == "command" {
            releaseCommand()
        } else if modifier == "control" {
            releaseControl()
        }
    }
}

func releaseShift() {
    mouseModifierFlags.remove(.maskShift)
    for keyCode: CGKeyCode in [56, 60] {
        if let event = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: keyCode,
            keyDown: false
        ) {
            event.flags = []
            event.post(tap: .cghidEventTap)
        }
    }
}

func releaseCommand() {
    mouseModifierFlags.remove(.maskCommand)
    for keyCode: CGKeyCode in [55, 54] {
        if let event = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: keyCode,
            keyDown: false
        ) {
            event.flags = []
            event.post(tap: .cghidEventTap)
        }
    }
}

func releaseControl() {
    for keyCode: CGKeyCode in [59, 62] {
        if let event = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: keyCode,
            keyDown: false
        ) {
            event.flags = []
            event.post(tap: .cghidEventTap)
        }
    }
}

func postScroll(_ vertical: Int32, _ horizontal: Int32) {
    if let event = CGEvent(
        scrollWheelEvent2Source: eventSource,
        units: .pixel,
        wheelCount: 2,
        wheel1: vertical,
        wheel2: horizontal,
        wheel3: 0
    ) {
        event.post(tap: .cghidEventTap)
    }
}

func postLayoutKey(virtualKey: CGKeyCode, down: Bool, shift: Bool) {
    if let event = CGEvent(
        keyboardEventSource: eventSource,
        virtualKey: virtualKey,
        keyDown: down
    ) {
        event.flags = shift ? .maskShift : []
        event.post(tap: .cghidEventTap)
    }
}

func postIsoKey(down: Bool, shift: Bool) {
    // macOS keycode 0x32 produces < and > in both French input sources.
    postLayoutKey(virtualKey: 0x32, down: down, shift: shift)
}

func postSquaredKey(down: Bool, shift: Bool) {
    // French-PC uses macOS keycode 0x0A for ² on the top-left key.
    postLayoutKey(virtualKey: 0x0A, down: down, shift: shift)
}

func clearModifiers() {
    // Recover from a modifier key-up lost while Moonlight changes focus.
    // These are key-up events only; the Linux bridge calls this only when no
    // modifier is physically held there.
    let currentFlags = CGEventSource.flagsState(.hidSystemState)
    if !currentFlags.contains(.maskCommand) &&
       !currentFlags.contains(.maskShift) &&
       !currentFlags.contains(.maskControl) &&
       !currentFlags.contains(.maskAlternate) {
        return
    }
    let modifierKeyCodes: [CGKeyCode] = [
        55, 54, // Command, Right Command
        56, 60, // Shift, Right Shift
        59, 62, // Control, Right Control
        58, 61  // Option, Right Option
    ]
    for keyCode in modifierKeyCodes {
        if let event = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: keyCode,
            keyDown: false
        ) {
            event.flags = []
            event.post(tap: .cghidEventTap)
        }
    }
}

func runSessionHelper(_ arguments: [String], failure: String) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: NSHomeDirectory() + "/.local/bin/mac-sunshine-session")
    process.arguments = arguments
    // Terminal/nohup can leave inherited descriptors unusable for Python.
    process.standardInput = FileHandle.nullDevice
    let log = FileHandle(forWritingAtPath: NSHomeDirectory() + "/.config/mac-mouse-bridge.log") ?? FileHandle.nullDevice
    _ = try? log.seekToEnd()
    process.standardOutput = log
    process.standardError = log
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? "READY" : "ERROR"
    } catch {
        fputs("\(failure): \(error)\n", stderr)
        return "ERROR"
    }
}

func handle(_ data: Data, reply: @escaping (String?) -> Void) {
    guard let message = String(data: data, encoding: .utf8) else { reply(nil); return }
    let fields = message.split(separator: " ")
    guard let command = fields.first else { reply(nil); return }

    switch command {
    case "M" where fields.count == 3:
        if let x = Double(fields[1]), let y = Double(fields[2]) {
            postMove(CGFloat(x), CGFloat(y))
        }
    case "B" where fields.count == 3:
        if let button = Int(fields[1]), let down = Int(fields[2]) {
            postButton(button, down: down != 0)
        }
    case "S" where fields.count == 2:
        if let down = Int(fields[1]) {
            setMouseModifier("shift", down: down != 0)
        }
    case "D" where fields.count == 2:
        if let down = Int(fields[1]) {
            setMouseModifier("command", down: down != 0)
        }
    case "V" where fields.count == 2:
        if let down = Int(fields[1]) {
            setMouseModifier("control", down: down != 0)
        }
    case "J":
        // Idle-defeating jitter: nudge one pixel and back, never mid-click.
        guard pressedButtons.isEmpty else { break }
        let home = lastPoint
        postMove(home.x + 1, home.y)
        queue.asyncAfter(deadline: .now() + 0.05) {
            if pressedButtons.isEmpty { postMove(home.x, home.y) }
        }
    case "R":
        releaseShift()
    case "Q":
        releaseCommand()
    case "W" where fields.count == 3:
        if let vertical = Int32(fields[1]), let horizontal = Int32(fields[2]) {
            postScroll(vertical, horizontal)
        }
    case "I" where fields.count == 3:
        if let down = Int(fields[1]), let shift = Int(fields[2]) {
            postIsoKey(down: down != 0, shift: shift != 0)
        }
    case "T" where fields.count == 3:
        if let down = Int(fields[1]), let shift = Int(fields[2]) {
            postSquaredKey(down: down != 0, shift: shift != 0)
        }
    case "C":
        clearModifiers()
    case "P":
        // Bringing the virtual screens up can take a minute. Keep it off the
        // input queue so the mouse stays responsive, and drop repeats while
        // one is running so the client's retries cannot pile up behind the
        // session lock.
        guard !sessionBusy else { reply(nil); return }
        sessionBusy = true
        sessionQueue.async {
            let answer = runSessionHelper(["prepare"], failure: "Could not prepare the Sunshine display session")
            queue.async { sessionBusy = false }
            reply(answer)
        }
        return
    case "K":
        // A slow prepare must never prevent live streams renewing their leases.
        releaseQueue.async {
            reply(runSessionHelper(["heartbeat"], failure: "Could not renew the Sunshine display lease"))
        }
        return
    case "L" where fields.count == 2:
        // The stream ended on purpose. Dropping its lease lets the Mac power
        // the virtual screens down right away instead of waiting it out.
        // (Not "R": that already releases the shift modifier.)
        let side = String(fields[1])
        releaseQueue.async {
            let answer = runSessionHelper(["release", side], failure: "Could not release the Sunshine display lease")
            reply(answer)
        }
        return
    default:
        break
    }
    reply(nil)
}

func receive(_ connection: NWConnection) {
    connection.receiveMessage { data, _, _, error in
        if let data, error == nil {
            handle(data) { reply in
                guard let reply else { return }
                // Wake/heartbeat/release clients use a fresh UDP port each time.
                // Retaining those flows exhausts Network.framework's UDP table,
                // blocking new Linux requests while mouse activity masks it.
                connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
        if error == nil {
            receive(connection)
        } else {
            connection.cancel()
        }
    }
}

let listener = try! NWListener(using: .udp, on: port)
listener.stateUpdateHandler = { state in
    if case .failed(let error) = state {
        fputs("mac-mouse-bridge listener failed: \(error)\n", stderr)
        exit(1)
    }
}
listener.newConnectionHandler = { connection in
    // The Linux laptop is on the private wired LAN. Keep the listener simple
    // here because Network.framework renders the peer differently for IPv4
    // and IPv4-mapped IPv6 routes; the bridge port is not exposed beyond LAN.
    connection.start(queue: queue)
    receive(connection)
}
listener.start(queue: queue)
dispatchMain()
