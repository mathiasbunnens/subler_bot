import Foundation

/// lsof's access fields plus identity readback, after the quiet-period check.
public enum FileReadinessPolicy {
    public static func isSafe(before: String, after: String?, lsofOutput: String, exitStatus: Int32) -> Bool {
        guard before == after, exitStatus == 0 || exitStatus == 1 else { return false }
        let fields = lsofOutput.split(separator: "\n")
        return !fields.contains("aw") && !fields.contains("au")
    }
}
