//! Whether a newer Tinypen is out, from GitHub's answer for the latest release, and when to ask.

use serde_json::Value;

/// A release newer than this copy.
#[derive(Clone, Debug, PartialEq)]
pub struct NewRelease {
    /// Without its `v`.
    pub version: String,
    /// The app for this processor, when the release carries it with its checksum.
    pub download: Option<Download>,
}

/// Where the app is, and the SHA-256 GitHub gives for it, which the download must match.
#[derive(Clone, Debug, PartialEq)]
pub struct Download {
    pub url: String,
    /// Lower case hex.
    pub sha256: String,
}

impl NewRelease {
    /// The latest release when it is newer than `current`, with `asset` when the release carries
    /// it; None when it is not newer, or the answer cannot be read, as when GitHub refuses or is down.
    pub fn newer(latest: &str, current: &str, asset: &str) -> Option<NewRelease> {
        let answer: Value = serde_json::from_str(latest).ok()?;
        let tag = answer.get("tag_name")?.as_str()?;
        let version = tag.strip_prefix('v').unwrap_or(tag);
        let (mut newest, mut mine) = (numbers(version)?, numbers(current)?);
        // 1.1 is 1.1.0.
        let length = newest.len().max(mine.len());
        newest.resize(length, 0);
        mine.resize(length, 0);
        if mine >= newest {
            return None;
        }
        let download = answer.get("assets").and_then(Value::as_array).and_then(|assets| {
            let found = assets.iter().find(|each| each.get("name").and_then(Value::as_str) == Some(asset))?;
            let url = found.get("browser_download_url")?.as_str()?;
            let sha256 = found.get("digest")?.as_str()?.strip_prefix("sha256:")?;
            Some(Download { url: url.into(), sha256: sha256.to_ascii_lowercase() })
        });
        Some(NewRelease { version: version.into(), download })
    }
}

/// 1.10.0 as [1, 10, 0], so it sorts after 1.9.2, as text it would not.
fn numbers(version: &str) -> Option<Vec<u64>> {
    version.split('.').map(|part| part.parse().ok()).collect()
}

pub const WEEK: u64 = 7 * 86_400;
pub const HOUR: u64 = 3_600;

/// Seconds to wait before checking whether a look is due, zero when it is: one look a week, by the
/// calendar. A timer stops while the computer sleeps, so one set a week ahead would run late by
/// every night of sleep; the wait is never more than an hour, and each check compares the date with
/// the last look's.
pub fn wait(last_look: u64, now: u64) -> u64 {
    (last_look + WEEK).saturating_sub(now).min(HOUR)
}

/// After an update, the menu says so for the rest of that day. The copy that installs the update
/// writes the version and the day, as yyyy-mm-dd in local time, just before the new copy takes over.
pub fn updated_marker(version: &str, today: &str) -> String {
    format!("{version} {today}")
}

/// The menu's line, while today is the day this version took over; None otherwise.
pub fn updated_line(marker: Option<&str>, current: &str, today: &str) -> Option<String> {
    let parts: Vec<&str> = marker?.split(' ').collect();
    (parts == [current, today]).then(|| format!("Updated to Tinypen {current}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// After an update, the menu says so for the rest of that day: the version and the day are
    /// written just before the new copy takes over.
    #[test]
    fn the_day_of_the_update_the_menu_says_so() {
        assert_eq!(updated_line(Some("1.1.1 2026-10-11"), "1.1.1", "2026-10-11"), Some("Updated to Tinypen 1.1.1".into()));
    }

    #[test]
    fn the_next_day_it_says_nothing() {
        assert_eq!(updated_line(Some("1.1.1 2026-10-11"), "1.1.1", "2026-10-12"), None);
    }

    /// Written for a version that did not start, as when the swap failed: nothing to say.
    #[test]
    fn a_marker_for_another_version_says_nothing() {
        assert_eq!(updated_line(Some("1.1.2 2026-10-11"), "1.1.1", "2026-10-11"), None);
        assert_eq!(updated_line(None, "1.1.1", "2026-10-11"), None);
        assert_eq!(updated_line(Some("nonsense"), "1.1.1", "2026-10-11"), None);
    }

    #[test]
    fn the_marker_holds_the_version_and_the_day() {
        assert_eq!(updated_marker("1.1.1", "2026-10-11"), "1.1.1 2026-10-11");
    }

    const DAY: u64 = 86_400;
    const ASSET: &str = "Tinypen-win-x64.exe";

    fn latest(tag: &str, assets: &[&str]) -> String {
        let list: Vec<String> = assets
            .iter()
            .map(|name| format!(r#"{{"name": "{name}", "browser_download_url": "https://example.com/{name}", "digest": "sha256:AB12"}}"#))
            .collect();
        format!(r#"{{"tag_name": "{tag}", "name": "Tinypen", "assets": [{}]}}"#, list.join(","))
    }

    #[test]
    fn a_newer_release_is_found_without_its_v_and_with_this_processors_app() {
        let release = NewRelease::newer(&latest("v1.1.0", &["Tinypen-mac.zip", "Tinypen-win-arm64.exe", ASSET]), "1.0.0", ASSET);
        let download = Download { url: format!("https://example.com/{ASSET}"), sha256: "ab12".into() };
        assert_eq!(release, Some(NewRelease { version: "1.1.0".into(), download: Some(download) }));
    }

    #[test]
    fn a_release_without_the_app_is_still_found() {
        let release = NewRelease::newer(&latest("v1.1.0", &["Tinypen-mac.zip"]), "1.0.0", ASSET);
        assert_eq!(release, Some(NewRelease { version: "1.1.0".into(), download: None }));
    }

    /// Without a checksum there is nothing to check the download against, so it is not installed.
    #[test]
    fn an_app_without_its_checksum_is_not_downloaded() {
        let answer = format!(r#"{{"tag_name": "v1.1.0", "assets": [{{"name": "{ASSET}", "browser_download_url": "https://example.com/a"}}]}}"#);
        assert_eq!(NewRelease::newer(&answer, "1.0.0", ASSET).unwrap().download, None);
    }

    #[test]
    fn the_same_or_an_older_release_is_not() {
        assert_eq!(NewRelease::newer(&latest("v1.0.0", &[]), "1.0.0", ASSET), None);
        assert_eq!(NewRelease::newer(&latest("v0.9.0", &[]), "1.0.0", ASSET), None);
        assert_eq!(NewRelease::newer(&latest("v1.0", &[]), "1.0.0", ASSET), None);
    }

    /// Compared number by number, so 1.10 comes after 1.9, as text it would not.
    #[test]
    fn versions_compare_as_numbers() {
        assert_eq!(NewRelease::newer(&latest("v1.10.0", &[]), "1.9.2", ASSET).unwrap().version, "1.10.0");
        assert!(NewRelease::newer(&latest("v1.0.1", &[]), "1.0", ASSET).is_some());
    }

    /// GitHub refusing, or down, answers with something else: no update, and the next look tries again.
    #[test]
    fn an_answer_that_is_not_a_release_is_nothing() {
        assert_eq!(NewRelease::newer(r#"{"message": "API rate limit exceeded"}"#, "1.0.0", ASSET), None);
        assert_eq!(NewRelease::newer("<html>", "1.0.0", ASSET), None);
        assert_eq!(NewRelease::newer(&latest("nightly", &[]), "1.0.0", ASSET), None);
    }

    #[test]
    fn a_look_is_due_a_week_after_the_last_one() {
        assert_eq!(wait(0, 1_000 * DAY), 0);
        assert_eq!(wait(100 * DAY, 107 * DAY), 0);
        assert_eq!(wait(100 * DAY, 120 * DAY), 0);
    }

    /// Two days after a look, it waits an hour and checks the date again, not five days.
    #[test]
    fn before_then_it_waits_an_hour_at_most() {
        assert_eq!(wait(100 * DAY, 102 * DAY), 3_600);
        assert_eq!(wait(100 * DAY, 107 * DAY - 1_800), 1_800);
    }

    /// Asleep for most of the week: the first check after waking finds the look due.
    #[test]
    fn time_spent_asleep_counts_towards_the_week() {
        let last_look = 100 * DAY;
        assert_eq!(wait(last_look, last_look + 3_600), 3_600);
        assert_eq!(wait(last_look, last_look + 3_600 + 7 * DAY), 0);
    }
}
