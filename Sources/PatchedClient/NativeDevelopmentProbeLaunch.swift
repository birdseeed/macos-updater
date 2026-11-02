/// Pure argument selection, with no I/O or authority. The app calls this only in
/// its DEBUG construction branch; release app construction always uses init().
public enum NativeDevelopmentProbeLaunch {
    public static func rawEndpoint(arguments: [String]) -> String? {
        guard arguments.count == 3, arguments[1] == "--controlled-local-network-probe" else { return nil }
        return arguments[2]
    }
}
