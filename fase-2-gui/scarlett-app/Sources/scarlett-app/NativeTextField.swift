import AppKit
import SwiftUI

/// NSTextField wrapped for SwiftUI. SwiftUI's own TextField has known
/// first-responder/typing bugs inside sheets and popovers on macOS 14+;
/// the AppKit field works everywhere.
struct NativeTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var autoFocus: Bool = false
    var onSubmit: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = placeholder
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: 13)
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        if autoFocus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                field.becomeFirstResponder()
                if field.currentEditor() == nil {
                    fputs("native field: focused but no editor\n", stderr)
                }
            }
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativeTextField
        init(_ parent: NativeTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                fputs("native field: keystroke -> \"\(field.stringValue)\"\n", stderr)
                parent.text = field.stringValue
            }
        }

        @objc func submit(_ sender: Any?) {
            parent.onSubmit?()
        }
    }
}