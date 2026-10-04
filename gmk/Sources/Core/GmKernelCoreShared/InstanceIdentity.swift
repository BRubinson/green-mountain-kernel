import CryptoKit
import Foundation

// LIVES IN THE BASE LAYER. Its own doc comment already said why: the client
// side and the daemon side both call it, so the hash cannot be allowed to drift
// between them, and a helper shared across a layer boundary cannot live above
// that boundary. Six lines of CryptoKit, no GRDB.

/// Shared instance-identity derivation: `{repo}_{first 4 hex of md5(abs path)}`.
///
/// The single Swift home of the convention `gm_session_startup.sh` mirrors in
/// shell. `GitContext` derives it on the client side and the daemon derives it
/// when resolving an instance, so one implementation is what keeps a session
/// from being filed under two different codes for the same checkout.
enum InstanceIdentity {
    /// Derives an instance identifier from repo name and path.
    ///
    /// - Parameters:
    ///   - repoName: The repository name.
    ///   - absolutePath: The absolute path to the repository.
    /// - Returns: The instance code in the form `{repoName}_{4 hex digits}`.
    static func code(repoName: String, absolutePath: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(absolutePath.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(repoName)_\(hex.prefix(4))"
    }
}
