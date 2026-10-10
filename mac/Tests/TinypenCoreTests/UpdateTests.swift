import Foundation
import Testing
@testable import TinypenCore

/// A newer release, from GitHub's answer for the latest one: its version when newer than this
/// copy, and the Mac app zipped, which a copy that updates itself downloads.
struct NewReleaseTests {
    private func latest(_ tag: String, assets: [String] = []) -> Data {
        let list = assets.map { #"{"name": "\#($0)", "browser_download_url": "https://example.com/\#($0)"}"# }
        return Data(#"{"tag_name": "\#(tag)", "name": "Tinypen", "assets": [\#(list.joined(separator: ","))]}"#.utf8)
    }

    @Test func aNewerReleaseIsFoundWithoutItsVAndWithTheMacZip() {
        let release = NewRelease.newer(in: latest("v1.1.0", assets: ["Tinypen-win-x64.exe", "Tinypen-mac.zip"]), than: "1.0.0")
        #expect(release == NewRelease(version: "1.1.0", download: URL(string: "https://example.com/Tinypen-mac.zip")))
    }

    @Test func aReleaseWithNoMacZipIsStillFound() {
        #expect(NewRelease.newer(in: latest("v1.1.0"), than: "1.0.0") == NewRelease(version: "1.1.0", download: nil))
    }

    @Test func theSameOrAnOlderReleaseIsNot() {
        #expect(NewRelease.newer(in: latest("v1.0.0"), than: "1.0.0") == nil)
        #expect(NewRelease.newer(in: latest("v0.9.0"), than: "1.0.0") == nil)
        #expect(NewRelease.newer(in: latest("v1.0"), than: "1.0.0") == nil)
    }

    /// Compared number by number, so 1.10 comes after 1.9, as text it would not.
    @Test func versionsCompareAsNumbers() {
        #expect(NewRelease.newer(in: latest("v1.10.0"), than: "1.9.2")?.version == "1.10.0")
        #expect(NewRelease.newer(in: latest("v1.0.1"), than: "1.0") != nil)
    }

    /// GitHub refusing, or down, answers with something else: no update, and the next look tries again.
    @Test func anAnswerThatIsNotAReleaseIsNothing() {
        #expect(NewRelease.newer(in: Data(#"{"message": "API rate limit exceeded"}"#.utf8), than: "1.0.0") == nil)
        #expect(NewRelease.newer(in: Data("<html>".utf8), than: "1.0.0") == nil)
        #expect(NewRelease.newer(in: latest("nightly"), than: "1.0.0") == nil)
    }
}

struct UpdateRouteTests {
    private let applications = "/Applications/Tinypen.app"

    @Test func aReleaseBuildItCanReplaceUpdatesItself() {
        #expect(UpdateRoute.of(path: applications, releaseSigned: true, writable: true) == .itself)
        #expect(UpdateRoute.of(path: "/Users/someone/Applications/Tinypen.app", releaseSigned: true, writable: true) == .itself)
    }

    /// Opened straight from the unzipped download, macOS runs it from a hidden copy no app may
    /// write to: it offers to move itself to Applications, from where it can.
    @Test func aReleaseBuildThatCannotWriteWhereItIsIsOfferedTheMove() {
        #expect(UpdateRoute.of(path: "/private/var/folders/x/AppTranslocation/1/d/Tinypen.app", releaseSigned: true, writable: false) == .move)
    }

    /// Already in Applications, on an account that may not change it: moving there again would
    /// fail at every start, so it is told where to download the new version instead.
    @Test func aReleaseBuildInApplicationsItCannotChangeIsTold() {
        #expect(UpdateRoute.of(path: applications, releaseSigned: true, writable: false) == .download)
    }

    /// Built on this Mac, it cannot tell a release build from anyone else's, so it is told where to get one.
    @Test func aCopyBuiltHereIsToldWhereToDownload() {
        #expect(UpdateRoute.of(path: applications, releaseSigned: false, writable: true) == .download)
        #expect(UpdateRoute.of(path: "/Users/someone/Downloads/Tinypen.app", releaseSigned: false, writable: false) == .download)
    }
}

/// One look a week by the calendar. A timer stops while the Mac sleeps, so the wait is checked
/// against the date of the last look at least once an hour rather than left to one long timer.
struct UpdateScheduleTests {
    private let day: TimeInterval = 86_400

    @Test func aLookIsDueAWeekAfterTheLastOne() {
        #expect(UpdateSchedule.wait(lastLook: 0, now: 1_000 * day) == 0)
        #expect(UpdateSchedule.wait(lastLook: 100 * day, now: 107 * day) == 0)
        #expect(UpdateSchedule.wait(lastLook: 100 * day, now: 120 * day) == 0)
    }

    /// Two days after a look, it waits an hour and checks the date again, not five days.
    @Test func beforeThenItWaitsAnHourAtMost() {
        #expect(UpdateSchedule.wait(lastLook: 100 * day, now: 102 * day) == 3_600)
        #expect(UpdateSchedule.wait(lastLook: 100 * day, now: 107 * day - 1_800) == 1_800)
    }

    /// Asleep for most of the week: the first check after waking finds the look due.
    @Test func timeSpentAsleepCountsTowardsTheWeek() {
        let lastLook = 100 * day
        #expect(UpdateSchedule.wait(lastLook: lastLook, now: lastLook + 3_600) == 3_600)
        #expect(UpdateSchedule.wait(lastLook: lastLook, now: lastLook + 3_600 + 7 * day) == 0)
    }
}
