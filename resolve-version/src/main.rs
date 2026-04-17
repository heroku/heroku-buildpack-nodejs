use clap::{Command, arg, value_parser};
use libherokubuildpack::inventory::artifact::{Arch, Os};
use nodejs_data::{NodejsArtifact, NodejsInventory, Version, VersionRange};
use std::env::consts;
use std::ops::Deref;

const VERSION_REQS_EXIT_CODE: i32 = 1;
const INVENTORY_EXIT_CODE: i32 = 2;
const UNSUPPORTED_OS_EXIT_CODE: i32 = 3;
const UNSUPPORTED_ARCH_EXIT_CODE: i32 = 4;

fn main() {
    let allow_wide_range = std::env::var("NODEJS_ALLOW_WIDE_RANGE")
        .map(|val| val == "true")
        .unwrap_or(false);

    let matches = Command::new("resolve_version")
        .arg(arg!(<inventory_path>))
        .arg(arg!(<node_version>))
        .arg(arg!(<lts_major_version>))
        .arg(arg!(--os <os>).value_parser(value_parser!(Os)))
        .arg(arg!(--arch <arch>).value_parser(value_parser!(Arch)))
        .get_matches();

    let inventory_path = matches
        .get_one::<String>("inventory_path")
        .expect("required argument");

    let node_version = matches
        .get_one::<String>("node_version")
        .expect("required argument");

    let lts_major_version = matches
        .get_one::<String>("lts_major_version")
        .map(|v| v.parse::<u64>().expect("must be a positive number"))
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

    let version_requirements = VersionRange::parse(node_version.as_str()).unwrap_or_else(|e| {
        eprintln!("Could not parse Version Requirements '{node_version}': {e}");
        std::process::exit(VERSION_REQS_EXIT_CODE);
    });

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
        println!(
            "{}",
            serde_json::json!({
                "version": artifact.version,
                "url": artifact.url,
                "checksum_type": artifact.checksum.name,
                "checksum_value": hex::encode(&artifact.checksum.value),
                "uses_wide_range": *uses_wide_range,
                "lts_upper_bound_enforced": *lts_upper_bound_enforced,
            })
        );
    } else {
        println!("No result");
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
) -> Option<(&'a NodejsArtifact, UsesWideRange, LtsUpperBoundEnforced)> {
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

    Some((
        lts_artifact.unwrap_or(resolved_artifact),
        UsesWideRange(uses_wide_range),
        LtsUpperBoundEnforced(lts_artifact.is_some()),
    ))
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
        toml::from_str(contents).unwrap()
    }
}
