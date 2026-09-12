import CryptoKit
import Foundation

// LIVES IN THE BASE LAYER. Its own doc comment already said why: the CLIENT
// side and the daemon side both call it so the hash cannot drift between them.
// A helper shared across the layer boundary cannot live above it — it was only
// sitting in the persistence target because it shared a FILE with
// SandboxRetarget, which does need GRDB. Six lines of CryptoKit, no database.

/// Shared instance-identity derivation: `{repo}_{first 4 hex of md5(abs path)}`.
/// The single Swift home of the convention gmcc_session_startup.sh mirrors in shell —
/// GitContext (the client side) and SandboxRetarget both call this so the hash can
/// never drift between the live and sandbox sides.
public enum InstanceIdentity {
    public static func code(repoName: String, absolutePath: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(absolutePath.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(repoName)_\(hex.prefix(4))"
    }
}
