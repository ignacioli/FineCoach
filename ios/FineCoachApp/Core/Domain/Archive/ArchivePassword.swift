import Foundation

public enum ArchivePasswordError: Error, Equatable, Sendable {
    case tooShort
}

/// Archive password (M2-FR-016). Exists in memory only (M2-FR-017): it is never persisted,
/// logged, or written into any file. Creation and import share the `BackupPassword` rule
/// -- at least 8 Unicode characters, canonically normalized, never truncated -- so a
/// password accepted at export is always accepted at import.
public struct ArchivePassword: Equatable, Sendable {
    public static let minimumCharacterCount = 8

    private let backupPassword: BackupPassword

    /// UTF-8 bytes of the canonically normalized password, fed to the key derivation.
    public var utf8: Data { backupPassword.utf8 }

    /// Export side: enforces the minimum length.
    public init(creating raw: String) throws {
        do {
            self.backupPassword = try BackupPassword(creating: raw)
        } catch {
            throw ArchivePasswordError.tooShort
        }
    }

    /// Import side: a wrong or too-short password is not a validation error; it simply
    /// fails to authenticate.
    public init(importing raw: String) throws {
        self.backupPassword = try BackupPassword(importing: raw)
    }
}
