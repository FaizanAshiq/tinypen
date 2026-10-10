import AppKit
import Carbon.HIToolbox
import TinypenCore

/// The keys Tinypen needs, held as system wide hotkeys while it shows something, so they reach it
/// whichever app is in front and never that app. Reported: drawing started from the menu bar left
/// the keyboard with the app in front, which macOS decides and Tinypen cannot, and Esc went to the
/// terminal behind the drawing. A hotkey reaches Tinypen every time, as the drawing hotkey does.
@MainActor
final class DrawingKeys {
    /// A key held, as the drawing layer would have heard it.
    struct Key {
        let code: UInt16
        let command: Bool
        let character: Character?
    }

    private var references: [EventHotKeyRef] = []
    private var held: [Key] = []
    private var holding: HeldKeys = .none
    private var handler: EventHandlerRef?
    private let onKey: (Key) -> Void

    /// Four character code "TNPK", apart from the drawing hotkeys' own.
    nonisolated private static let signature: OSType = 0x544E_504B

    init(onKey: @escaping (Key) -> Void) {
        self.onKey = onKey
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            // Another signature is the drawing hotkeys', left for their own handler.
            guard status == noErr, identifier.signature == DrawingKeys.signature else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                let keys = Unmanaged<DrawingKeys>.fromOpaque(userData).takeUnretainedValue()
                let index = Int(identifier.id)
                if keys.held.indices.contains(index) { keys.onKey(keys.held[index]) }
            }
            return noErr
        }, 1, &spec, context, &handler)
    }

    /// Holds the keys `set` names and lets the rest go. A key another app holds already is left to
    /// the drawing layer.
    func hold(_ set: HeldKeys) {
        guard set != holding else { return }
        release()
        holding = set
        let typed: [Character]
        switch set {
        case .none: return
        case .escape: typed = []
        case .all: typed = Tool.allCases.map(\.key) + ["w", "1", "2", "3", "4", "5", "6", "[", "]"]
        }
        var keys = [Key(code: UInt16(kVK_Escape), command: false, character: nil)]
        keys += typed.compactMap { character in Self.code(typing: character).map { Key(code: $0, command: false, character: character) } }
        if set == .all {
            keys += [Key(code: UInt16(kVK_Delete), command: false, character: nil),
                     Key(code: UInt16(kVK_ForwardDelete), command: false, character: nil)]
            if let z = Self.code(typing: "z") { keys.append(Key(code: z, command: true, character: "z")) }
        }
        for key in keys {
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(key.code), key.command ? UInt32(cmdKey) : 0,
                                             EventHotKeyID(signature: Self.signature, id: UInt32(held.count)),
                                             GetApplicationEventTarget(), 0, &reference)
            guard status == noErr, let reference else { continue }
            references.append(reference)
            held.append(key)
        }
    }

    func release() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        held.removeAll()
        holding = .none
    }

    /// The key that types `character` on the keyboard layout in use, so a French or German
    /// keyboard holds its own A, not the key where an American one has it.
    private static func code(typing character: Character) -> UInt16? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return data.withUnsafeBytes { bytes -> UInt16? in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            for code in UInt16(0)..<128 {
                var deadKeys: UInt32 = 0
                var length = 0
                var typed = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, typed.count, &length, &typed)
                if status == noErr, length == 1, String(utf16CodeUnits: typed, count: 1).lowercased() == String(character) {
                    return code
                }
            }
            return nil
        }
    }
}
