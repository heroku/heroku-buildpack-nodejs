use chrono::Utc;
use clap::{Command, arg, value_parser};
use libherokubuildpack::inventory::artifact::{Arch, Os};
use node_semver::{Range, Version as SemverVersion};
use nodejs_data::{NodeReleaseSchedule, NodejsArtifact, NodejsInventory, Version, VersionRange};
use std::env::consts;
use std::ops::Deref;

const VERSION_REQS_EXIT_CODE: i32 = 1;
const INVENTORY_EXIT_CODE: i32 = 2;
const UNSUPPORTED_OS_EXIT_CODE: i32 = 3;
const UNSUPPORTED_ARCH_EXIT_CODE: i32 = 4;
const SCHEDULE_EXIT_CODE: i32 = 5;

fn main() {
    let allow_wide_range = std::env::var("NODEJS_ALLOW_WIDE_RANGE")
        .map(|val| val == "true")
        .unwrap_or(false);

    let matches = Command::new("resolve_version")
        .arg(arg!(<inventory_path>))
        .arg(arg!(<schedule_path>))
        .arg(arg!([node_version]))
        .arg(arg!(--os <os>).value_parser(value_parser!(Os)))
        .arg(arg!(--arch <arch>).value_parser(value_parser!(Arch)))
        .get_matches();

    let inventory_path = matches
        .get_one::<String>("inventory_path")
        .expect("required argument");

    let schedule_path = matches
        .get_one::<String>("schedule_path")
        .expect("required argument");

    let os = match matches.get_one::<Os>("os") {
        Some(os) => *os,
        None => consts::OS.parse::<Os>().unwrap_or_else(|e| {
            eprintln!("Unsupported OS '{}': {e}", consts::OS);
            std::process::exit(UNSUPPORTED_OS_EXIT_CODE);
        }),
    };

    let arch = match matches.get_one::<Arch>("arch") {
        Some(arch) => *arch,
        None => consts::ARCH.parse::<Arch>().unwrap_or_else(|e| {
            eprintln!("Unsupported Architecture '{}': {e}", consts::ARCH);
            std::process::exit(UNSUPPORTED_ARCH_EXIT_CODE);
        }),
    };

    let schedule_contents = std::fs::read_to_string(schedule_path).unwrap_or_else(|e| {
        eprintln!("Error reading '{schedule_path}': {e}");
        std::process::exit(SCHEDULE_EXIT_CODE);
    });

    let schedule = NodeReleaseSchedule::from_json(&schedule_contents).unwrap_or_else(|e| {
        eprintln!("Error parsing '{schedule_path}': {e}");
        std::process::exit(SCHEDULE_EXIT_CODE);
    });

    let now = Utc::now();

    let newest_lts = schedule
        .newest_supported_lts(now)
        .expect("Release schedule should contain at least one supported LTS version");

    let lts_major_version = newest_lts.requirement.to_string();
    let lts_major_version = lts_major_version
        .trim_start_matches('v')
        .parse::<i64>()
        .expect("LTS requirement should be a major version like 'v24'");

    let version_requirements = match matches.get_one::<String>("node_version") {
        Some(node_version) => VersionRange::parse(node_version.as_str()).unwrap_or_else(|e| {
            eprintln!("Could not parse Version Requirements '{node_version}': {e}");
            std::process::exit(VERSION_REQS_EXIT_CODE);
        }),
        None => newest_lts.requirement.clone(),
    };

    let inventory_contents = std::fs::read_to_string(inventory_path).unwrap_or_else(|e| {
        eprintln!("Error reading '{inventory_path}': {e}");
        std::process::exit(INVENTORY_EXIT_CODE);
    });

    let node_inventory: NodejsInventory = toml::from_str(&inventory_contents).unwrap_or_else(|e| {
        eprintln!("Error parsing '{inventory_path}': {e}");
        std::process::exit(INVENTORY_EXIT_CODE);
    });

    if let Some((artifact, uses_wide_range, lts_upper_bound_enforced)) = resolve_node_artifact(
        &node_inventory,
        os,
        arch,
        &version_requirements,
        lts_major_version,
        allow_wide_range,
    ) {
        let warning = eol_warning(&schedule, &artifact.version, now);

        let mut json = serde_json::json!({
            "version": artifact.version,
            "url": artifact.url,
            "checksum_type": artifact.checksum.name,
            "checksum_value": hex::encode(&artifact.checksum.value),
            "uses_wide_range": *uses_wide_range,
            "lts_upper_bound_enforced": *lts_upper_bound_enforced,
        });

        if let Some(warning) = warning {
            json["warning"] = serde_json::Value::String(warning);
        }

        println!("{json}");
    } else {
        println!("No result");
    }
}

fn eol_warning(
    schedule: &NodeReleaseSchedule,
    version: &Version,
    now: chrono::DateTime<Utc>,
) -> Option<String> {
    let release = schedule.resolve(version)?;
    if !release.is_eol(now) {
        return None;
    }
    let supported_lts = schedule.supported_lts_labels(now).join(", ");
    Some(format!(
        "Node.js {} reached its official End-of-Life (EOL) on {}.\n\
         It no longer receives security updates, bug fixes, or support from the\n\
         Node.js project and is no longer supported on Heroku.\n\
         \n\
         In a future buildpack release, this warning will become a build error.\n\
         Please upgrade to a supported version as soon as possible to avoid\n\
         build failures.\n\
         \n\
         Supported LTS releases: {}\n\
         \n\
         For more information, see:\n\
         https://devcenter.heroku.com/articles/nodejs-support#supported-node-js-versions",
        release.requirement,
        release.end_of_life.format("%B %e, %Y"),
        supported_lts,
    ))
}

fn resolve_node_artifact<'a>(
    node_inventory: &'a NodejsInventory,
    os: Os,
    arch: Arch,
    requirement: &VersionRange,
    lts_major_version: i64,
    allow_wide_range: bool,
) -> Option<(&'a NodejsArtifact, UsesWideRange, LtsUpperBoundEnforced)> {
    let lts_range_value = format!("{lts_major_version}.x");
    let lts_range = VersionRange::parse(&lts_range_value)
        .unwrap_or_else(|_| panic!("Range {lts_range_value} should be valid"));

    if let Some(resolved_artifact) = node_inventory.resolve(os, arch, requirement)
        && let Some(highest_lts_artifact) = node_inventory.resolve(os, arch, &lts_range)
    {
        // The wide-range/LTS logic below needs node_semver::Range for min_version()
        // which nodejs-data's VersionRange doesn't expose. We bridge by parsing a local
        // Range from VersionRange's Display output, replicating the transformations
        // nodejs-data applies for syntax node_semver doesn't understand ("latest", "~=").
        // This can be removed once the logic moves into the shared crate.
        let requirement_str = requirement.to_string();
        let raw_range = if requirement_str == "latest" {
            Range::any()
        } else if requirement_str.starts_with("~=") {
            Range::parse(requirement_str.replacen('=', "", 1))
                .expect("VersionRange should produce a valid Range string")
        } else {
            Range::parse(&requirement_str)
                .expect("VersionRange should produce a valid Range string")
        };

        let uses_wide_range = if raw_range.satisfies(&SemverVersion::new(
            resolved_artifact.version.major() - 1,
            0,
            0,
        )) || raw_range.satisfies(&SemverVersion::new(
            resolved_artifact.version.major() + 1,
            0,
            0,
        )) {
            UsesWideRange(true)
        } else {
            UsesWideRange(false)
        };

        // raw_range.min_version() returns a node_semver::Version, so we need to
        // convert the nodejs-data versions for comparison.
        let resolved_semver = SemverVersion::parse(resolved_artifact.version.to_string()).unwrap();
        let lts_semver = SemverVersion::parse(highest_lts_artifact.version.to_string()).unwrap();

        let lts_upper_bound_enforced = if allow_wide_range {
            LtsUpperBoundEnforced(false)
        } else if resolved_semver > lts_semver
            && let Some(min_version) = raw_range.min_version()
            && min_version <= lts_semver
        {
            LtsUpperBoundEnforced(true)
        } else {
            LtsUpperBoundEnforced(false)
        };
        Some((
            if *lts_upper_bound_enforced {
                highest_lts_artifact
            } else {
                resolved_artifact
            },
            uses_wide_range,
            lts_upper_bound_enforced,
        ))
    } else {
        None
    }
}

struct UsesWideRange(bool);

impl Deref for UsesWideRange {
    type Target = bool;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

struct LtsUpperBoundEnforced(bool);

impl Deref for LtsUpperBoundEnforced {
    type Target = bool;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::str::FromStr;

    const TEST_LTS_MAJOR_VERSION: i64 = 24;
    const ALLOW_WIDE_RANGE: bool = true;
    const DISALLOW_WIDE_RANGE: bool = false;

    #[test]
    fn parse_handles_latest() {
        let result = VersionRange::parse("latest");

        assert!(result.is_ok());
        if let Ok(reqs) = result {
            assert_eq!("latest", reqs.to_string());
        }
    }

    #[test]
    fn parse_handles_exact_versions() {
        let result = VersionRange::parse("14.0.0");

        assert!(result.is_ok());
        if let Ok(reqs) = result {
            assert_eq!("14.0.0", reqs.to_string());
        }
    }

    #[test]
    fn parse_handles_starts_with_v() {
        let result = VersionRange::parse("v14.0.0");

        assert!(result.is_ok());
        if let Ok(reqs) = result {
            assert_eq!("v14.0.0", reqs.to_string());
        }
    }

    #[test]
    fn parse_handles_semver_semantics() {
        let result = VersionRange::parse(">= 12.0.0");

        assert!(result.is_ok());
        if let Ok(reqs) = result {
            assert_eq!(">= 12.0.0", reqs.to_string());
        }
    }

    #[test]
    fn parse_handles_pipe_statements() {
        let result = VersionRange::parse("^12 || ^13 || ^14");

        assert!(result.is_ok());
        if let Ok(reqs) = result {
            assert_eq!("^12 || ^13 || ^14", reqs.to_string());
        }
    }

    #[test]
    fn parse_handles_tilde_with_equals() {
        let result = VersionRange::parse("~=14.4");

        assert!(result.is_ok());
        if let Ok(reqs) = result {
            assert_eq!("~=14.4", reqs.to_string());
        }
    }

    #[test]
    fn parse_handles_tilde_with_equals_and_patch() {
        let result = VersionRange::parse("~=14.4.3");

        assert!(result.is_ok());
        if let Ok(reqs) = result {
            assert_eq!("~=14.4.3", reqs.to_string());
        }
    }

    #[test]
    fn parse_handles_v_within_string() {
        let result = VersionRange::parse(">v15.5.0");

        assert!(result.is_ok());
        if let Ok(reqs) = result {
            assert_eq!(">v15.5.0", reqs.to_string());
        }
    }

    #[test]
    fn parse_handles_v_with_space() {
        let result = VersionRange::parse(">= v10.0.0");

        assert!(result.is_ok());
        if let Ok(reqs) = result {
            assert_eq!(">= v10.0.0", reqs.to_string());
        }
    }

    #[test]
    fn parse_handles_equal_with_v() {
        let result = VersionRange::parse("=v10.22.0");

        assert!(result.is_ok());
        if let Ok(reqs) = result {
            assert_eq!("=v10.22.0", reqs.to_string());
        }
    }

    #[test]
    fn parse_returns_error_for_invalid_reqs() {
        let result = VersionRange::parse("12.%");
        assert!(result.is_err());
    }

    #[test]
    fn resolve_version_when_wide_range_used_and_version_is_downgraded_to_lts() {
        let wide_requirement = VersionRange::parse(">= 22").unwrap();
        let inventory = create_inventory();
        let (artifact, show_wide_range_warning, show_downgrade_warning) = resolve_node_artifact(
            &inventory,
            Os::Linux,
            Arch::Amd64,
            &wide_requirement,
            TEST_LTS_MAJOR_VERSION,
            DISALLOW_WIDE_RANGE,
        )
        .unwrap();
        assert_eq!(artifact.version.major(), 24);
        assert!(*show_wide_range_warning);
        assert!(*show_downgrade_warning);
    }

    #[test]
    fn resolve_version_when_narrow_range_used_and_version_is_not_downgraded_to_lts() {
        let wide_requirement = VersionRange::parse("22.x").unwrap();
        let inventory = create_inventory();
        let (artifact, show_wide_range_warning, show_downgrade_warning) = resolve_node_artifact(
            &inventory,
            Os::Linux,
            Arch::Amd64,
            &wide_requirement,
            TEST_LTS_MAJOR_VERSION,
            DISALLOW_WIDE_RANGE,
        )
        .unwrap();
        assert_eq!(artifact.version.major(), 22);
        assert!(!*show_wide_range_warning);
        assert!(!*show_downgrade_warning);
    }

    #[test]
    fn resolve_version_when_exact_range_used_and_version_is_not_downgraded_to_lts() {
        let wide_requirement = VersionRange::parse("22.21.0").unwrap();
        let inventory = create_inventory();
        let (artifact, show_wide_range_warning, show_downgrade_warning) = resolve_node_artifact(
            &inventory,
            Os::Linux,
            Arch::Amd64,
            &wide_requirement,
            TEST_LTS_MAJOR_VERSION,
            DISALLOW_WIDE_RANGE,
        )
        .unwrap();
        assert_eq!(artifact.version.major(), 22);
        assert!(!*show_wide_range_warning);
        assert!(!*show_downgrade_warning);
    }

    #[test]
    fn resolve_version_when_wide_range_used_and_version_is_lts() {
        let wide_requirement = VersionRange::parse(">= 24").unwrap();
        let inventory = create_inventory();
        let (artifact, show_wide_range_warning, show_downgrade_warning) = resolve_node_artifact(
            &inventory,
            Os::Linux,
            Arch::Amd64,
            &wide_requirement,
            TEST_LTS_MAJOR_VERSION,
            DISALLOW_WIDE_RANGE,
        )
        .unwrap();
        assert_eq!(artifact.version.major(), 24);
        assert!(*show_wide_range_warning);
        assert!(*show_downgrade_warning);
    }

    #[test]
    fn resolve_version_when_narrow_range_used_and_version_is_lts() {
        let wide_requirement = VersionRange::parse("24.x").unwrap();
        let inventory = create_inventory();
        let (artifact, show_wide_range_warning, show_downgrade_warning) = resolve_node_artifact(
            &inventory,
            Os::Linux,
            Arch::Amd64,
            &wide_requirement,
            TEST_LTS_MAJOR_VERSION,
            DISALLOW_WIDE_RANGE,
        )
        .unwrap();
        assert_eq!(artifact.version.major(), 24);
        assert!(!*show_wide_range_warning);
        assert!(!*show_downgrade_warning);
    }

    #[test]
    fn resolve_version_when_exact_lts_range_used() {
        let wide_requirement = VersionRange::parse("24.10.0").unwrap();
        let inventory = create_inventory();
        let (artifact, show_wide_range_warning, show_downgrade_warning) = resolve_node_artifact(
            &inventory,
            Os::Linux,
            Arch::Amd64,
            &wide_requirement,
            TEST_LTS_MAJOR_VERSION,
            DISALLOW_WIDE_RANGE,
        )
        .unwrap();
        assert_eq!(artifact.version.major(), 24);
        assert!(!*show_wide_range_warning);
        assert!(!*show_downgrade_warning);
    }

    #[test]
    fn resolve_version_when_wide_range_is_used_and_explicitly_requesting_range_beyond_lts() {
        let wide_requirement = VersionRange::parse(">=25.x").unwrap();
        let inventory = create_inventory();
        let (artifact, show_wide_range_warning, show_downgrade_warning) = resolve_node_artifact(
            &inventory,
            Os::Linux,
            Arch::Amd64,
            &wide_requirement,
            TEST_LTS_MAJOR_VERSION,
            DISALLOW_WIDE_RANGE,
        )
        .unwrap();
        assert_eq!(artifact.version.major(), 25);
        assert!(*show_wide_range_warning);
        assert!(!*show_downgrade_warning);
    }

    #[test]
    fn resolve_version_when_narrow_range_is_used_and_explicitly_requesting_range_beyond_lts() {
        let wide_requirement = VersionRange::parse("25.x").unwrap();
        let inventory = create_inventory();
        let (artifact, show_wide_range_warning, show_downgrade_warning) = resolve_node_artifact(
            &inventory,
            Os::Linux,
            Arch::Amd64,
            &wide_requirement,
            TEST_LTS_MAJOR_VERSION,
            DISALLOW_WIDE_RANGE,
        )
        .unwrap();
        assert_eq!(artifact.version.major(), 25);
        assert!(!*show_wide_range_warning);
        assert!(!*show_downgrade_warning);
    }

    #[test]
    fn resolve_version_when_exact_range_is_used_and_explicitly_requesting_range_beyond_lts() {
        let wide_requirement = VersionRange::parse("25.0.0").unwrap();
        let inventory = create_inventory();
        let (artifact, show_wide_range_warning, show_downgrade_warning) = resolve_node_artifact(
            &inventory,
            Os::Linux,
            Arch::Amd64,
            &wide_requirement,
            TEST_LTS_MAJOR_VERSION,
            DISALLOW_WIDE_RANGE,
        )
        .unwrap();
        assert_eq!(artifact.version.major(), 25);
        assert!(!*show_wide_range_warning);
        assert!(!*show_downgrade_warning);
    }

    #[test]
    fn resolve_version_with_complex_range_with_upper_bound_within_lts() {
        let wide_requirement = VersionRange::parse(">=22.x <25.x").unwrap();
        let inventory = create_inventory();
        let (artifact, show_wide_range_warning, show_downgrade_warning) = resolve_node_artifact(
            &inventory,
            Os::Linux,
            Arch::Amd64,
            &wide_requirement,
            TEST_LTS_MAJOR_VERSION,
            DISALLOW_WIDE_RANGE,
        )
        .unwrap();
        assert_eq!(artifact.version.major(), 24);
        assert!(*show_wide_range_warning);
        assert!(!*show_downgrade_warning);
    }

    #[test]
    fn resolve_version_with_complex_range_with_upper_bound_beyond_lts() {
        let wide_requirement = VersionRange::parse(">=25.x <27.x").unwrap();
        let inventory = create_inventory();
        let (artifact, show_wide_range_warning, show_downgrade_warning) = resolve_node_artifact(
            &inventory,
            Os::Linux,
            Arch::Amd64,
            &wide_requirement,
            TEST_LTS_MAJOR_VERSION,
            DISALLOW_WIDE_RANGE,
        )
        .unwrap();
        assert_eq!(artifact.version.major(), 25);
        assert!(*show_wide_range_warning);
        assert!(!*show_downgrade_warning);
    }

    #[test]
    fn resolve_version_with_complex_range_with_lower_and_upper_bounds_within_lts() {
        let wide_requirement = VersionRange::parse(">=24.x <25.x").unwrap();
        let inventory = create_inventory();
        let (artifact, show_wide_range_warning, show_downgrade_warning) = resolve_node_artifact(
            &inventory,
            Os::Linux,
            Arch::Amd64,
            &wide_requirement,
            TEST_LTS_MAJOR_VERSION,
            DISALLOW_WIDE_RANGE,
        )
        .unwrap();
        assert_eq!(artifact.version.major(), 24);
        assert!(!*show_wide_range_warning);
        assert!(!*show_downgrade_warning);
    }

    #[test]
    fn resolve_version_with_wide_range_environment_override_to_prevent_downgrade() {
        let wide_requirement = VersionRange::parse(">=22.x").unwrap();
        let inventory = create_inventory();
        let (artifact, show_wide_range_warning, show_downgrade_warning) = resolve_node_artifact(
            &inventory,
            Os::Linux,
            Arch::Amd64,
            &wide_requirement,
            TEST_LTS_MAJOR_VERSION,
            ALLOW_WIDE_RANGE,
        )
        .unwrap();
        assert_eq!(artifact.version.major(), 25);
        assert!(*show_wide_range_warning);
        assert!(!*show_downgrade_warning);
    }

    #[test]
    fn eol_warning_returns_warning_for_eol_version() {
        let schedule = test_schedule();
        let now = chrono::TimeZone::with_ymd_and_hms(&Utc, 2025, 6, 1, 0, 0, 0).unwrap();
        let version = Version::parse("18.20.8").unwrap();
        let warning = eol_warning(&schedule, &version, now);
        assert!(warning.is_some());
        let text = warning.unwrap();
        assert!(text.contains("v18"));
        assert!(text.contains("End-of-Life"));
        assert!(text.contains("v20"));
    }

    #[test]
    fn eol_warning_returns_none_for_supported_version() {
        let schedule = test_schedule();
        let now = chrono::TimeZone::with_ymd_and_hms(&Utc, 2025, 6, 1, 0, 0, 0).unwrap();
        let version = Version::parse("20.11.0").unwrap();
        let warning = eol_warning(&schedule, &version, now);
        assert!(warning.is_none());
    }

    #[test]
    fn eol_warning_returns_none_for_unknown_version() {
        let schedule = test_schedule();
        let now = chrono::TimeZone::with_ymd_and_hms(&Utc, 2025, 6, 1, 0, 0, 0).unwrap();
        let version = Version::parse("99.0.0").unwrap();
        let warning = eol_warning(&schedule, &version, now);
        assert!(warning.is_none());
    }

    fn test_schedule() -> NodeReleaseSchedule {
        NodeReleaseSchedule::from_json(
            r#"{
                "v18": { "lts": "2022-10-25", "end": "2025-04-30" },
                "v20": { "lts": "2023-10-24", "end": "2026-04-30" },
                "v21": { "end": "2024-06-01" }
            }"#,
        )
        .unwrap()
    }

    fn create_inventory() -> NodejsInventory {
        let contents = r#"
            [[artifacts]]
            version = "25.0.0"
            os = "linux"
            arch = "amd64"
            url = "https://nodejs.org/download/release/v25.0.0/node-v25.0.0-linux-x64.tar.gz"
            checksum = "sha256:28dd46a6733192647d7c8267343f5a3f1c616f773c448e2c0d2539ae70724b40"

            [[artifacts]]
            version = "24.10.0"
            os = "linux"
            arch = "amd64"
            url = "https://nodejs.org/download/release/v24.10.0/node-v24.10.0-linux-x64.tar.gz"
            checksum = "sha256:2b03c5417ce0b1076780df00e01da373bead3b4b80d1c78c1ad10ee7b918d90c"

            [[artifacts]]
            version = "22.21.0"
            os = "linux"
            arch = "amd64"
            url = "https://nodejs.org/download/release/v22.21.0/node-v22.21.0-linux-x64.tar.gz"
            checksum = "sha256:262b84b02f7e2bc017d4bdb81fec85ca0d6190a5cd0781d2d6e84317c08871f8"
        "#;
        NodejsInventory::from_str(contents).unwrap()
    }
}
