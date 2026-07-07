use clap::{Command, arg, value_parser};
use libherokubuildpack::inventory::artifact::{Arch, Os};
use nodejs_data::{
    NodejsArtifact, NodejsInventory, RECOMMENDED_LTS_VERSION, SUPPORTED_NODEJS_VERSIONS, Version,
    VersionError, VersionRange,
};
use serde::Serialize;
use std::env::consts;
use std::process::ExitCode;

struct Resolution<'a> {
    artifact: &'a NodejsArtifact,
    uses_wide_range: bool,
    lts_upper_bound_enforced: bool,
    eol: bool,
}

/// The resolver's structured output. Serialized to stdout as a single JSON object in every case,
/// with a `status` discriminator. Success returns exit code 0; every error variant returns exit
/// code 1. This lets the shell caller branch on `status` without parsing prose or exit codes.
#[derive(Serialize)]
#[serde(tag = "status", rename_all = "kebab-case")]
enum Output {
    /// A version was resolved from the inventory.
    Resolved {
        version: Version,
        url: String,
        checksum_type: String,
        checksum_value: String,
        uses_wide_range: bool,
        lts_upper_bound_enforced: bool,
        default: bool,
        lts_version: String,
        eol: bool,
    },
    /// The requirement parsed as valid semver, but no inventory version matched it.
    NoVersionResolved { error: String, lts_major: u64 },
    /// The requested version requirement was not a valid semver range.
    InvalidSemverRequirement { error: String, lts_major: u64 },
    /// A catastrophic error the app can't fix: inventory read/parse failure, unsupported OS/arch,
    /// or an inventory missing the recommended LTS. `lts_major` is omitted when it can't be
    /// computed (e.g. the inventory couldn't be read).
    InternalError {
        error: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        lts_major: Option<u64>,
    },
}

/// Prints the output as a single line of JSON to stdout.
fn emit(output: &Output) {
    println!(
        "{}",
        serde_json::to_string(output).expect("Output is always serializable")
    );
}

fn main() -> ExitCode {
    let allow_wide_range = std::env::var("NODEJS_ALLOW_WIDE_RANGE")
        .map(|val| val == "true")
        .unwrap_or(false);

    let matches = Command::new("resolve_version")
        .arg(arg!(<inventory_path>))
        .arg(arg!(<node_version>))
        .arg(arg!(--os <os>).value_parser(value_parser!(Os)))
        .arg(arg!(--arch <arch>).value_parser(value_parser!(Arch)))
        .get_matches();

    let inventory_path = matches
        .get_one::<String>("inventory_path")
        .expect("required argument");

    let node_version = matches
        .get_one::<String>("node_version")
        .expect("required argument");

    // OS/arch are resolved before the inventory is read, so `lts_major` can't be computed yet if
    // either is unsupported.
    let os = match matches.get_one::<Os>("os") {
        Some(os) => *os,
        None => match consts::OS.parse::<Os>() {
            Ok(os) => os,
            Err(e) => {
                emit(&Output::InternalError {
                    error: format!("Unsupported OS '{}': {e}", consts::OS),
                    lts_major: None,
                });
                return ExitCode::FAILURE;
            }
        },
    };

    let arch = match matches.get_one::<Arch>("arch") {
        Some(arch) => *arch,
        None => match consts::ARCH.parse::<Arch>() {
            Ok(arch) => arch,
            Err(e) => {
                emit(&Output::InternalError {
                    error: format!("Unsupported Architecture '{}': {e}", consts::ARCH),
                    lts_major: None,
                });
                return ExitCode::FAILURE;
            }
        },
    };

    let default = node_version.is_empty();

    // Read and parse the inventory before parsing the requirement so that `lts_major` is available
    // to the invalid-semver-requirement path below.
    let inventory_contents = match std::fs::read_to_string(inventory_path) {
        Ok(contents) => contents,
        Err(e) => {
            emit(&Output::InternalError {
                error: format!("Error reading '{inventory_path}': {e}"),
                lts_major: None,
            });
            return ExitCode::FAILURE;
        }
    };

    let node_inventory: NodejsInventory = match toml::from_str(&inventory_contents) {
        Ok(inventory) => inventory,
        Err(e) => {
            emit(&Output::InternalError {
                error: format!("Error parsing '{inventory_path}': {e}"),
                lts_major: None,
            });
            return ExitCode::FAILURE;
        }
    };

    let lts_major_version = match node_inventory.resolve(os, arch, &*RECOMMENDED_LTS_VERSION) {
        Some(artifact) => artifact.version.major(),
        None => {
            emit(&Output::InternalError {
                error: format!(
                    "Inventory does not contain a version matching RECOMMENDED_LTS_VERSION ({})",
                    *RECOMMENDED_LTS_VERSION
                ),
                lts_major: None,
            });
            return ExitCode::FAILURE;
        }
    };

    let requirement = match parse_node_version(node_version) {
        Ok(requirement) => requirement,
        Err(e) => {
            emit(&Output::InvalidSemverRequirement {
                error: format!("Could not parse Version Requirements '{node_version}': {e}"),
                lts_major: lts_major_version,
            });
            return ExitCode::FAILURE;
        }
    };

    match resolve_node_artifact(
        &node_inventory,
        os,
        arch,
        &requirement,
        lts_major_version,
        allow_wide_range,
    ) {
        Some(resolution) => {
            emit(&Output::Resolved {
                version: resolution.artifact.version.clone(),
                url: resolution.artifact.url.clone(),
                checksum_type: resolution.artifact.checksum.name.clone(),
                checksum_value: hex::encode(&resolution.artifact.checksum.value),
                uses_wide_range: resolution.uses_wide_range,
                lts_upper_bound_enforced: resolution.lts_upper_bound_enforced,
                default,
                lts_version: RECOMMENDED_LTS_VERSION.to_string(),
                eol: resolution.eol,
            });
            ExitCode::SUCCESS
        }
        None => {
            emit(&Output::NoVersionResolved {
                error: format!(
                    "No published Node.js version matches the requirement '{node_version}'"
                ),
                lts_major: lts_major_version,
            });
            ExitCode::FAILURE
        }
    }
}

fn parse_node_version(node_version: &str) -> Result<VersionRange, VersionError> {
    if node_version.is_empty() {
        Ok(RECOMMENDED_LTS_VERSION.clone())
    } else {
        VersionRange::parse(node_version)
    }
}

fn is_wide_range(requirement: &VersionRange, resolved_major: u64) -> bool {
    if let Some(next) = resolved_major.checked_add(1)
        && requirement.satisfies(&Version::new(next, 0, 0))
    {
        return true;
    }
    if let Some(prev) = resolved_major.checked_sub(1)
        && requirement.satisfies(&Version::new(prev, 0, 0))
    {
        return true;
    }
    false
}

fn find_lts_ceiling<'a>(
    requirement: &VersionRange,
    resolved_version: &Version,
    inventory: &'a NodejsInventory,
    os: Os,
    arch: Arch,
    lts_major_version: u64,
) -> Option<&'a NodejsArtifact> {
    inventory
        .artifacts
        .iter()
        .filter(|a| {
            a.os == os
                && a.arch == arch
                && a.version.major() == lts_major_version
                && requirement.satisfies(&a.version)
        })
        .max_by_key(|a| a.version.clone())
        .filter(|lts_artifact| resolved_version > &lts_artifact.version)
}

fn resolve_node_artifact<'a>(
    node_inventory: &'a NodejsInventory,
    os: Os,
    arch: Arch,
    requirement: &VersionRange,
    lts_major_version: u64,
    allow_wide_range: bool,
) -> Option<Resolution<'a>> {
    let resolved_artifact = node_inventory.resolve(os, arch, requirement)?;
    let uses_wide_range = is_wide_range(requirement, resolved_artifact.version.major());

    let lts_artifact = if allow_wide_range {
        None
    } else {
        find_lts_ceiling(
            requirement,
            &resolved_artifact.version,
            node_inventory,
            os,
            arch,
            lts_major_version,
        )
    };

    let artifact = lts_artifact.unwrap_or(resolved_artifact);

    Some(Resolution {
        eol: !SUPPORTED_NODEJS_VERSIONS.contains(&artifact.version.major()),
        artifact,
        uses_wide_range,
        lts_upper_bound_enforced: lts_artifact.is_some(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEST_LTS_MAJOR_VERSION: u64 = 24;
    const ALLOW_WIDE_RANGE: bool = true;
    const DISALLOW_WIDE_RANGE: bool = false;

    // --- is_wide_range tests ---

    #[test]
    fn wide_range_detected_for_open_ended_range() {
        assert!(is_wide_range(&VersionRange::parse(">= 22").unwrap(), 25));
    }

    #[test]
    fn wide_range_not_detected_for_single_major() {
        assert!(!is_wide_range(&VersionRange::parse("22.x").unwrap(), 22));
    }

    #[test]
    fn wide_range_not_detected_for_exact_version() {
        assert!(!is_wide_range(&VersionRange::parse("22.21.0").unwrap(), 22));
    }

    #[test]
    fn wide_range_detected_for_range_starting_at_highest_major() {
        assert!(is_wide_range(&VersionRange::parse(">= 24").unwrap(), 25));
    }

    #[test]
    fn wide_range_detected_for_range_starting_above_highest_major() {
        assert!(is_wide_range(&VersionRange::parse(">=25.x").unwrap(), 25));
    }

    #[test]
    fn wide_range_not_detected_for_narrow_lts_range() {
        assert!(!is_wide_range(&VersionRange::parse("24.x").unwrap(), 24));
    }

    #[test]
    fn wide_range_detected_for_complex_range_spanning_majors() {
        assert!(is_wide_range(
            &VersionRange::parse(">=22.x <25.x").unwrap(),
            24
        ));
    }

    #[test]
    fn wide_range_detected_for_complex_range_above_lts() {
        assert!(is_wide_range(
            &VersionRange::parse(">=25.x <27.x").unwrap(),
            25
        ));
    }

    #[test]
    fn wide_range_not_detected_for_complex_range_within_single_major() {
        assert!(!is_wide_range(
            &VersionRange::parse(">=24.x <25.x").unwrap(),
            24
        ));
    }

    #[test]
    fn wide_range_not_detected_for_major_zero() {
        assert!(!is_wide_range(&VersionRange::parse("0.x").unwrap(), 0));
    }

    #[test]
    fn wide_range_detected_for_star_range_at_major_zero() {
        assert!(is_wide_range(&VersionRange::parse("*").unwrap(), 0));
    }

    // --- find_lts_ceiling tests ---

    fn assert_lts_ceiling(range: &str, expected: bool) {
        let inventory = create_inventory();
        let requirement = VersionRange::parse(range).unwrap();
        let resolved_version = inventory
            .resolve(Os::Linux, Arch::Amd64, &requirement)
            .unwrap_or_else(|| panic!("expected resolution to succeed for range '{range}'"))
            .version
            .clone();
        assert_eq!(
            find_lts_ceiling(
                &requirement,
                &resolved_version,
                &inventory,
                Os::Linux,
                Arch::Amd64,
                TEST_LTS_MAJOR_VERSION,
            )
            .is_some(),
            expected,
            "wrong lts ceiling for range '{range}'"
        );
    }

    #[test]
    fn lts_ceiling_found_when_wide_range_resolves_above_lts() {
        assert_lts_ceiling(">= 22", true);
    }

    #[test]
    fn lts_ceiling_not_found_for_narrow_range_below_lts() {
        assert_lts_ceiling("22.x", false);
    }

    #[test]
    fn lts_ceiling_not_found_for_exact_version_below_lts() {
        assert_lts_ceiling("22.21.0", false);
    }

    #[test]
    fn lts_ceiling_found_when_range_starts_at_lts_and_resolves_above() {
        assert_lts_ceiling(">= 24", true);
    }

    #[test]
    fn lts_ceiling_not_found_for_narrow_lts_range() {
        assert_lts_ceiling("24.x", false);
    }

    #[test]
    fn lts_ceiling_not_found_for_exact_lts_version() {
        assert_lts_ceiling("24.10.0", false);
    }

    #[test]
    fn lts_ceiling_not_found_when_range_starts_above_lts() {
        assert_lts_ceiling(">=25.x", false);
    }

    #[test]
    fn lts_ceiling_not_found_for_narrow_range_above_lts() {
        assert_lts_ceiling("25.x", false);
    }

    #[test]
    fn lts_ceiling_not_found_for_exact_version_above_lts() {
        assert_lts_ceiling("25.0.0", false);
    }

    #[test]
    fn lts_ceiling_not_found_for_complex_range_with_upper_bound_within_lts() {
        assert_lts_ceiling(">=22.x <25.x", false);
    }

    #[test]
    fn lts_ceiling_not_found_for_complex_range_above_lts() {
        assert_lts_ceiling(">=25.x <27.x", false);
    }

    #[test]
    fn lts_ceiling_not_found_for_complex_range_within_single_lts_major() {
        assert_lts_ceiling(">=24.x <25.x", false);
    }

    // --- End-to-end resolution tests ---

    fn assert_resolution(
        range: &str,
        allow_wide_range: bool,
        expected_major: u64,
        expected_wide: bool,
        expected_lts_enforced: bool,
    ) {
        let inventory = create_inventory();
        let requirement = VersionRange::parse(range).unwrap();
        let resolution = resolve_node_artifact(
            &inventory,
            Os::Linux,
            Arch::Amd64,
            &requirement,
            TEST_LTS_MAJOR_VERSION,
            allow_wide_range,
        )
        .unwrap_or_else(|| panic!("expected resolution to succeed for range '{range}'"));
        assert_eq!(
            resolution.artifact.version.major(),
            expected_major,
            "wrong major for range '{range}'"
        );
        assert_eq!(
            resolution.uses_wide_range, expected_wide,
            "wrong uses_wide_range for range '{range}'"
        );
        assert_eq!(
            resolution.lts_upper_bound_enforced, expected_lts_enforced,
            "wrong lts_enforced for range '{range}'"
        );
    }

    #[test]
    fn e2e_wide_range_downgraded_to_lts() {
        assert_resolution(">= 22", DISALLOW_WIDE_RANGE, 24, true, true);
    }

    #[test]
    fn e2e_wide_range_not_downgraded_when_allowed() {
        assert_resolution(">=22.x", ALLOW_WIDE_RANGE, 25, true, false);
    }

    #[test]
    fn e2e_narrow_range_resolves_without_downgrade() {
        assert_resolution("22.x", DISALLOW_WIDE_RANGE, 22, false, false);
    }

    #[test]
    fn e2e_exact_version_above_lts_not_downgraded() {
        assert_resolution("25.0.0", DISALLOW_WIDE_RANGE, 25, false, false);
    }

    #[test]
    fn e2e_wide_range_starting_at_lts_downgraded() {
        assert_resolution(">= 24", DISALLOW_WIDE_RANGE, 24, true, true);
    }

    #[test]
    fn e2e_star_range_downgraded_to_lts() {
        assert_resolution("*", DISALLOW_WIDE_RANGE, 24, true, true);
    }

    #[test]
    fn e2e_complex_range_within_lts() {
        assert_resolution(">=22.x <25.x", DISALLOW_WIDE_RANGE, 24, true, false);
    }

    #[test]
    fn e2e_complex_range_beyond_lts() {
        assert_resolution(">=25.x <27.x", DISALLOW_WIDE_RANGE, 25, true, false);
    }

    #[test]
    fn e2e_complex_range_within_single_lts_major() {
        assert_resolution(">=24.x <25.x", DISALLOW_WIDE_RANGE, 24, false, false);
    }

    #[test]
    fn e2e_lts_not_enforced_when_no_lts_artifact_exists() {
        let inventory = create_inventory();
        let requirement = VersionRange::parse(">= 22").unwrap();
        let non_existent_lts: u64 = 23;
        let resolution = resolve_node_artifact(
            &inventory,
            Os::Linux,
            Arch::Amd64,
            &requirement,
            non_existent_lts,
            DISALLOW_WIDE_RANGE,
        )
        .expect("expected resolution to succeed");
        assert_eq!(resolution.artifact.version.major(), 25);
        assert!(resolution.uses_wide_range);
        assert!(!resolution.lts_upper_bound_enforced);
    }

    #[test]
    fn e2e_no_matching_version_returns_none() {
        let inventory = create_inventory();
        let requirement = VersionRange::parse("99.x").unwrap();
        assert!(
            resolve_node_artifact(
                &inventory,
                Os::Linux,
                Arch::Amd64,
                &requirement,
                TEST_LTS_MAJOR_VERSION,
                DISALLOW_WIDE_RANGE,
            )
            .is_none()
        );
    }

    #[test]
    fn empty_version_uses_recommended_lts() {
        let result = parse_node_version("");
        assert_eq!(
            result.unwrap().to_string(),
            RECOMMENDED_LTS_VERSION.to_string()
        );
    }

    #[test]
    fn non_empty_version_parses_as_given() {
        let result = parse_node_version("22.x");
        assert_eq!(result.unwrap().to_string(), "22.x");
    }

    // --- EOL detection tests ---

    #[test]
    fn eol_true_for_unsupported_version() {
        let inventory = create_inventory();
        let requirement = VersionRange::parse("18.x").unwrap();
        let resolution = resolve_node_artifact(
            &inventory,
            Os::Linux,
            Arch::Amd64,
            &requirement,
            TEST_LTS_MAJOR_VERSION,
            DISALLOW_WIDE_RANGE,
        )
        .expect("expected resolution to succeed");
        assert_eq!(resolution.artifact.version.major(), 18);
        assert!(resolution.eol);
    }

    #[test]
    fn eol_false_for_supported_version() {
        let inventory = create_inventory();
        let requirement = VersionRange::parse("24.x").unwrap();
        let resolution = resolve_node_artifact(
            &inventory,
            Os::Linux,
            Arch::Amd64,
            &requirement,
            TEST_LTS_MAJOR_VERSION,
            DISALLOW_WIDE_RANGE,
        )
        .expect("expected resolution to succeed");
        assert_eq!(resolution.artifact.version.major(), 24);
        assert!(!resolution.eol);
    }

    // --- Output serialization contract tests ---

    #[test]
    fn resolved_output_has_status_and_all_fields() {
        let output = Output::Resolved {
            version: Version::new(24, 10, 0),
            url: "https://example.com/node.tar.gz".to_string(),
            checksum_type: "sha256".to_string(),
            checksum_value: "abc123".to_string(),
            uses_wide_range: false,
            lts_upper_bound_enforced: true,
            default: false,
            lts_version: "24.x".to_string(),
            eol: false,
        };
        let value = serde_json::to_value(&output).unwrap();
        assert_eq!(value["status"], "resolved");
        assert_eq!(value["version"], "24.10.0");
        assert_eq!(value["url"], "https://example.com/node.tar.gz");
        assert_eq!(value["checksum_type"], "sha256");
        assert_eq!(value["checksum_value"], "abc123");
        assert_eq!(value["uses_wide_range"], false);
        assert_eq!(value["lts_upper_bound_enforced"], true);
        assert_eq!(value["default"], false);
        assert_eq!(value["lts_version"], "24.x");
        assert_eq!(value["eol"], false);
    }

    #[test]
    fn no_version_resolved_output_carries_lts_major() {
        let output = Output::NoVersionResolved {
            error: "no match".to_string(),
            lts_major: 24,
        };
        let value = serde_json::to_value(&output).unwrap();
        assert_eq!(value["status"], "no-version-resolved");
        assert_eq!(value["error"], "no match");
        assert_eq!(value["lts_major"], 24);
    }

    #[test]
    fn invalid_semver_requirement_output_carries_lts_major() {
        let output = Output::InvalidSemverRequirement {
            error: "bad semver".to_string(),
            lts_major: 24,
        };
        let value = serde_json::to_value(&output).unwrap();
        assert_eq!(value["status"], "invalid-semver-requirement");
        assert_eq!(value["error"], "bad semver");
        assert_eq!(value["lts_major"], 24);
    }

    #[test]
    fn internal_error_output_omits_lts_major_when_none() {
        let output = Output::InternalError {
            error: "inventory unreadable".to_string(),
            lts_major: None,
        };
        let value = serde_json::to_value(&output).unwrap();
        assert_eq!(value["status"], "internal-error");
        assert_eq!(value["error"], "inventory unreadable");
        assert!(
            value.get("lts_major").is_none(),
            "lts_major key should be absent, not null, when None"
        );
    }

    #[test]
    fn internal_error_output_includes_lts_major_when_some() {
        let output = Output::InternalError {
            error: "missing recommended lts".to_string(),
            lts_major: Some(24),
        };
        let value = serde_json::to_value(&output).unwrap();
        assert_eq!(value["status"], "internal-error");
        assert_eq!(value["lts_major"], 24);
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

            [[artifacts]]
            version = "18.20.8"
            os = "linux"
            arch = "amd64"
            url = "https://nodejs.org/download/release/v18.20.8/node-v18.20.8-linux-x64.tar.gz"
            checksum = "sha256:27a9f3f14d5e99ad05a07ed3524ba3ee92f8ff8b6db5ff80b00f9feb5ec8097a"
        "#;
        toml::from_str(contents).unwrap()
    }
}
