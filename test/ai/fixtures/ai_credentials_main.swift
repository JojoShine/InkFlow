import Foundation
import Security
func check(_ condition: @autoclosure () throws -> Bool) throws { let result = try condition(); precondition(result) }
let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: root) }
let id = String(repeating: "a", count: 64)
var migrations = 0
let store = AiCredentialStore(root: root) { _ in migrations += 1; return "legacy-test-key" }
try check(!store.contains(id))
precondition(migrations == 0)
try check(try store.read(id) == "legacy-test-key")
try check(try store.read(id) == "legacy-test-key")
precondition(migrations == 1)
let reopened = AiCredentialStore(root: root) { _ in fatalError("Restart must use the persisted key") }
try check(try reopened.read(id) == "legacy-test-key")
try reopened.write(id, key: "updated-test-key")
try check(try reopened.read(id) == "updated-test-key")
try check(reopened.contains(id))
let permissions = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(id + ".key").path)
precondition((permissions[.posixPermissions] as! NSNumber).intValue == 0o600)
let directoryPermissions = try FileManager.default.attributesOfItem(atPath: root.path)
precondition((directoryPermissions[.posixPermissions] as! NSNumber).intValue == 0o700)
try reopened.delete(id)
try check(!reopened.contains(id))
try check(try reopened.read(id) == nil)
try check(try AiCredentialStore(root: root) { _ in fatalError("Deleted key must not migrate again") }.read(id) == nil)
let missing = String(repeating: "b", count: 64)
let absent = AiCredentialStore(root: root) { _ in nil }
try check(try absent.read(missing) == nil)
var priorInteraction: DarwinBoolean = false
precondition(SecKeychainGetUserInteractionAllowed(&priorInteraction) == errSecSuccess)
let probe = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
_ = try AiCredentialStore(root: root).read(probe + probe)
var restoredInteraction: DarwinBoolean = false
precondition(SecKeychainGetUserInteractionAllowed(&restoredInteraction) == errSecSuccess)
precondition(priorInteraction.boolValue == restoredInteraction.boolValue)
print("Native persistence, migration, deletion and file permissions passed")
