import CoreGraphics
import Foundation

enum TypewriterSimulator {
    static func typeText(_ text: String, baseInterval: Double, useRandom: Bool, min minInterval: Double, max maxInterval: Double) async {
        guard !text.isEmpty else { return }
        let fixedInterval = Swift.max(0.001, baseInterval)
        let lower = Swift.max(0.001, Swift.min(minInterval, maxInterval))
        let upper = Swift.max(lower, Swift.max(minInterval, maxInterval))

        for char in text {
            let s = String(char)
            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                continue
            }
            let utf16 = Array(s.utf16)
            utf16.withUnsafeBufferPointer { pointer in
                guard let baseAddress = pointer.baseAddress else { return }
                keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: baseAddress)
                keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: baseAddress)
            }
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)

            let interval = useRandom ? Double.random(in: lower...upper) : fixedInterval
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }
}
