import Foundation

/// A release newer than this copy, as GitHub's answer for the latest release names it.
public struct NewRelease: Equatable, Sendable {
    /// Without its `v`.
    public let version: String
    /// The Mac app zipped, when the release carries one: what a copy that updates itself downloads.
    public let download: URL?

    public init(version: String, download: URL?) {
        self.version = version
        self.download = download
    }

    /// The latest release when it is newer than `current`; nil when it is not, or the answer cannot
    /// be read, as when GitHub refuses or is down.
    public static func newer(in latest: Data, than current: String) -> NewRelease? {
        guard let answer = try? JSONSerialization.jsonObject(with: latest) as? [String: Any],
              let tag = answer["tag_name"] as? String else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard var newest = numbers(version), var mine = numbers(current) else { return nil }
        // 1.1 is 1.1.0.
        let length = max(newest.count, mine.count)
        newest += Array(repeating: 0, count: length - newest.count)
        mine += Array(repeating: 0, count: length - mine.count)
        guard mine.lexicographicallyPrecedes(newest) else { return nil }
        let assets = answer["assets"] as? [[String: Any]] ?? []
        let zip = assets.first { $0["name"] as? String == "Tinypen-mac.zip" }?["browser_download_url"] as? String
        return NewRelease(version: version, download: zip.flatMap(URL.init(string:)))
    }

    /// 1.10.0 as [1, 10, 0], so it sorts after 1.9.2, as text it would not.
    private static func numbers(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".").map { Int($0) }
        return parts.isEmpty || parts.contains(nil) ? nil : parts.compactMap { $0 }
    }
}

/// How a copy of the Mac app gets a newer version, from how it was signed and where it runs.
public enum UpdateRoute: Equatable, Sendable {
    /// A release build where it can replace itself: it downloads the update and installs it.
    case itself
    /// A release build opened straight from the unzipped download, which macOS runs from a hidden
    /// copy no app may write to: offered a move to Applications, from where it updates itself.
    case move
    /// Built on this Mac, so it cannot tell a release build from anyone else's, or in Applications
    /// where this account may not write: told where to download one.
    case download

    public static let applications = "/Applications/Tinypen.app"

    public static func of(path: String, releaseSigned: Bool, writable: Bool) -> UpdateRoute {
        guard releaseSigned else { return .download }
        if writable { return .itself }
        return path == applications ? .download : .move
    }
}

/// When to look for a newer release: once a week, by the calendar.
public enum UpdateSchedule {
    public static let week: TimeInterval = 7 * 86_400
    public static let hour: TimeInterval = 3_600

    /// Seconds to wait before checking whether a look is due, zero when it is. A timer stops while
    /// the Mac sleeps, so one set a week ahead would run late by every night of sleep; the wait is
    /// never more than an hour, and each check compares the date with the last look's.
    public static func wait(lastLook: TimeInterval, now: TimeInterval) -> TimeInterval {
        min(max(0, lastLook + week - now), hour)
    }
}

/// After an update, the menu says so for the rest of that day. The copy that installs the update
/// writes the version and the day just before the new copy takes over.
public enum UpdatedNote {
    /// "1.1.1 2026-10-11"; the day as yyyy-MM-dd in local time.
    public static func marker(version: String, today: String) -> String {
        "\(version) \(today)"
    }

    /// The menu's line, while today is the day this version took over; nil otherwise.
    public static func line(marker: String?, current: String, today: String) -> String? {
        let parts = (marker ?? "").split(separator: " ").map(String.init)
        guard parts == [current, today] else { return nil }
        return "Updated to Tinypen \(current)"
    }
}
