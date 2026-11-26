/// Format a version string from short version and build number.
/// Returns "X.Y.Z (build)" for a typical version, or just the build if short is empty.
public func hearthVersionString(short: String, build: String) -> String {
    if short.isEmpty {
        return build
    }
    return "\(short) (\(build))"
}
