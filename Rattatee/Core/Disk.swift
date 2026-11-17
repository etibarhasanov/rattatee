import Foundation

/// What the phone keeps between launches: every ride, one JSON file each,
/// in Application Support under `rides/`.
///
/// A ride is written here while it is being recorded — every few points and
/// at every pause — and stays until it is removed by hand, so a ride the
/// server has not confirmed can never be lost to a crash, a killed app or a
/// dead battery. Files are written atomically: a ride is the old file or the
/// new one, never half of each.
enum Disk {
    static var rides: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = root.appendingPathComponent("rides", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // The rides are the user's own and only on this phone until they
            // upload; keeping them in a backup is what keeps them past a
            // lost phone. So they are not excluded from iCloud backup.
        }
        return dir
    }

    static func all() -> [Data] {
        let files = (try? FileManager.default.contentsOfDirectory(at: rides, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { try? Data(contentsOf: $0) }
    }

    static func write(_ data: Data, _ id: String) {
        // Writable while the phone is locked, which is when a ride is being
        // written: complete protection would refuse the write in a pocket.
        try? data.write(to: rides.appendingPathComponent("\(id).json"),
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func remove(_ id: String) {
        try? FileManager.default.removeItem(at: rides.appendingPathComponent("\(id).json"))
    }

    /// A file compiled into the app. Xcode's synchronised folder copies the
    /// resources flat into the bundle, but this also looks under `Seed/` in
    /// case a future project setting keeps the folder.
    static func seed(_ name: String) -> Data? {
        let url = Bundle.main.url(forResource: name, withExtension: "json")
            ?? Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Seed")
        return url.flatMap { try? Data(contentsOf: $0) }
    }
}
