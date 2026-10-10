import AppKit
import Carbon.HIToolbox
import TinypenCore

/// System wide hotkeys through Carbon's RegisterEventHotKey, which needs no
/// Accessibility permission.
///
/// One handler serves every hotkey and dispatches on the id Carbon hands back. A handler
/// per hotkey, which is enough for a single one, breaks with several: every
/// handler hears every press, and the first to answer swallows it, so one hotkey would
/// fire another's action.
@MainActor
final class HotKeyCenter {
    private var references: [HotKeyAction: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private let onFire: (HotKeyAction) -> Void

    /// Four character code "TNPN".
    nonisolated private static let signature: OSType = 0x544E_504E

    init(onFire: @escaping (HotKeyAction) -> Void) {
        self.onFire = onFire

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == HotKeyCenter.signature,
                  let action = HotKeyCenter.action(for: identifier.id) else { return OSStatus(eventNotHandledErr) }
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue().onFire(action)
            }
            return noErr
        }, 1, &spec, context, &handler)
    }

    /// Registers every bound hotkey, replacing what was there. Returns the actions whose
    /// combination could not be had, because another app already holds it.
    @discardableResult
    func register(_ hotkeys: HotKeys) -> Set<HotKeyAction> {
        unregisterAll()
        var taken: Set<HotKeyAction> = []
        for action in HotKeyAction.allCases {
            guard let binding = hotkeys[action] else { continue }
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(binding.keyCode,
                                             Self.carbonModifiers(binding.modifiers),
                                             EventHotKeyID(signature: Self.signature, id: Self.id(for: action)),
                                             GetApplicationEventTarget(),
                                             OptionBits(kEventHotKeyExclusive),
                                             &reference)
            if status == noErr, let reference {
                references[action] = reference
            } else {
                taken.insert(action)
            }
        }
        return taken
    }

    func unregisterAll() {
        references.values.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
    }

    private static func id(for action: HotKeyAction) -> UInt32 {
        UInt32((HotKeyAction.allCases.firstIndex(of: action) ?? 0) + 1)
    }

    nonisolated private static func action(for id: UInt32) -> HotKeyAction? {
        let actions = HotKeyAction.allCases
        let index = Int(id) - 1
        return actions.indices.contains(index) ? actions[index] : nil
    }

    private static func carbonModifiers(_ modifiers: [ModifierKey]) -> UInt32 {
        var mask: UInt32 = 0
        for modifier in modifiers {
            switch modifier {
            case .control: mask |= UInt32(controlKey)
            case .option: mask |= UInt32(optionKey)
            case .shift: mask |= UInt32(shiftKey)
            case .command: mask |= UInt32(cmdKey)
            }
        }
        return mask
    }
}
