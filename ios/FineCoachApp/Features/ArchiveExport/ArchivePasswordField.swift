import SwiftUI
import UIKit

// The ONE configuration of an archive password entry (M2-FR-015, AC-004, adversarial review #3).
// The export password fields (M2-05) and, later, the import password fields (M2-08, M2-19) must
// all be built with `ArchivePasswordField`; a static test asserts that nothing else configures
// text input traits for passwords.
//
// What the configuration does and why:
// - Masked entry (`FCTextField` secure mode).
// - No text content type is declared. Declaring a password-type content type would invite the
//   system to offer saving the password to the Keychain and to suggest a generated one; an
//   archive password must never be stored by the system. The empty content type below also
//   switches off the heuristic that treats a masked field as a credential.
// - No autocorrection and no automatic capitalization, so the Coach types exactly what the
//   student will type.
// Whether the system still offers a save or suggestion prompt is a device-only check (D-12).

struct ArchivePasswordEntryConfiguration: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textContentType(UITextContentType(rawValue: ""))
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.never)
    }
}

extension View {
    /// Applies the shared archive password entry traits. Prefer `ArchivePasswordField`.
    func archivePasswordEntry() -> some View {
        modifier(ArchivePasswordEntryConfiguration())
    }
}

/// A masked archive password field. Never logs, stores or names anything after its content.
struct ArchivePasswordField: View {
    private let title: String
    @Binding private var text: String

    init(_ title: String, text: Binding<String>) {
        self.title = title
        self._text = text
    }

    var body: some View {
        FCTextField(title, text: $text, isSecure: true)
            .archivePasswordEntry()
    }
}
