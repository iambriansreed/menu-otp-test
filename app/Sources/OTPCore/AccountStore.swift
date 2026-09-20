import CryptoKit
import Foundation

public struct StoreLoad: Equatable, Sendable {
    public var accounts: [Account]
    /// Set when an unreadable accounts.enc was moved here instead of being loaded.
    /// The app must tell the user: they are looking at an empty list.
    public var setAside: URL?

    public init(accounts: [Account], setAside: URL? = nil) {
        self.accounts = accounts
        self.setAside = setAside
    }
}

public enum AccountStoreError: LocalizedError {
    case cannotSetAside(file: URL, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case let .cannotSetAside(file, underlying):
            "\(file.lastPathComponent) couldn't be read, and moving it aside failed "
                + "(\(underlying.localizedDescription)). Nothing was changed."
        }
    }
}

/// accounts.enc: "MOTP1" followed by an AES-256-GCM sealed box (nonce + ciphertext +
/// tag) of the JSON-encoded `[Account]`.
public final class AccountStore {
    static let magic = Data("MOTP1".utf8)

    public let fileURL: URL
    private let keyProvider: KeyProvider

    public init(fileURL: URL, keyProvider: KeyProvider) {
        self.fileURL = fileURL
        self.keyProvider = keyProvider
    }

    /// No file yet -> no accounts, without touching the Keychain, so a first launch
    /// doesn't prompt until there is something to save.
    ///
    /// A key that can't be *obtained* (Keychain denied, locked, errored) throws and
    /// leaves the file alone: the caller must stop rather than save over it.
    ///
    /// A file that can't be *decrypted or parsed* with a key we do have is moved
    /// aside to `accounts.enc.unreadable-<epoch>` and reported in `setAside`. The
    /// Electron app deleted such a file outright; moving it keeps a recovery path for
    /// the only copy of the user's secrets. If even the move fails this throws, so
    /// the next save can't replace the file.
    public func load() throws -> StoreLoad {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return StoreLoad(accounts: []) }
        let key = try keyProvider.key()
        let data = try Data(contentsOf: fileURL)
        do {
            guard data.starts(with: Self.magic) else { throw CocoaError(.fileReadCorruptFile) }
            let box = try AES.GCM.SealedBox(combined: data.dropFirst(Self.magic.count))
            let json = try AES.GCM.open(box, using: key)
            return StoreLoad(accounts: try JSONDecoder().decode([Account].self, from: json))
        } catch {
            let aside = fileURL.deletingLastPathComponent().appendingPathComponent(
                "\(fileURL.lastPathComponent).unreadable-\(Int(Date().timeIntervalSince1970))"
            )
            do {
                try FileManager.default.moveItem(at: fileURL, to: aside)
            } catch {
                throw AccountStoreError.cannotSetAside(file: fileURL, underlying: error)
            }
            return StoreLoad(accounts: [], setAside: aside)
        }
    }

    /// Encrypts to a temp file beside the real one, then rename(2)s it into place.
    /// rename is atomic on one volume, so a crash mid-write leaves the old file or
    /// the new one, never half of one (which load() would treat as unreadable).
    public func save(_ accounts: [Account]) throws {
        let key = try keyProvider.key()
        let json = try JSONEncoder().encode(accounts)
        guard let sealed = try AES.GCM.seal(json, using: key).combined else {
            throw CocoaError(.fileWriteUnknown)
        }
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent("\(fileURL.lastPathComponent).tmp")
        guard FileManager.default.createFile(
            atPath: tmp.path, contents: Self.magic + sealed, attributes: [.posixPermissions: 0o600]
        ) else { throw CocoaError(.fileWriteUnknown) }
        guard rename(tmp.path, fileURL.path) == 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSUnderlyingErrorKey: POSIXError(.init(rawValue: errno) ?? .EIO)])
        }
    }
}
