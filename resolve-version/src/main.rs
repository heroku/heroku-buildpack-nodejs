use clap::{Command, arg, value_parser};
use libherokubuildpack::inventory::artifact::{Arch, Os};
use nodejs_data::{NodejsArtifact, NodejsInventory, Version, VersionRange};
use std::collections::HashSet;
use std::env::consts;

const VERSION_REQS_EXIT_CODE: i32 = 1;
const INVENTORY_EXIT_CODE: i32 = 2;
const UNSUPPORTED_OS_EXIT_CODE: i32 = 3;
const UNSUPPORTED_ARCH_EXIT_CODE: i32 = 4;

fn is_wide_range(requirement: &VersionRange, inventory: &NodejsInventory) -> bool {
    let mut majors = HashSet::new();
    for artifact in &inventory.artifacts {
        if requirement.satisfies(&artifact.version) {
            majors.insert(artifact.version.major());
        }
    }
    if majors.len() > 1 {
        return true;
    }
    if let Some(&highest) = majors.iter().max()
        && let Ok(next_major) = Version::parse(&format!("{}.0.0", highest + 1))
    {
        return requirement.satisfies(&next_major);
    }
    false
}

fn lts_upper_bound(
    requirement: &VersionRange,
    inventory: &NodejsInventory,
    lts_major_version: u64,
) -> Option<Version> {
    inventory
        .artifacts
        .iter()
        .filter(|a| a.version.major() == lts_major_version && requirement.satisfies(&a.version))
        .map(|a| &a.version)
        .max()
        .cloned()
}

fn should_enforce_lts_upper_bound(
    requirement: &VersionRange,
    inventory: &NodejsInventory,
    os: Os,
    arch: Arch,
    lts_major_version: u64,
) -> bool {
    if let Some(lts_version) = lts_upper_bound(requirement, inventory, lts_major_version) {
        inventory
            .resolve(os, arch, requirement)
            .is_some_and(|resolved| resolved.version > lts_version)
    } else {
        false
    }
}

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

    let requirement = VersionRange::parse(node_version.as_str()).unwrap_or_else(|e| {
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

    let uses_wide_range = is_wide_range(&requirement, &node_inventory);

    let lts_upper_bound_enforced = !allow_wide_range
        && should_enforce_lts_upper_bound(
            &requirement,
            &node_inventory,
            os,
            arch,
            lts_major_version,
        );

    let requirement = if lts_upper_bound_enforced {
        VersionRange::parse(&format!("{lts_major_version}.x")).expect("LTS range should be valid")
    } else {
        requirement
    };

    if let Some(artifact) = node_inventory.resolve(os, arch, &requirement) {
        println!(
            "{}",
            serde_json::json!({
                "version": artifact.version,
                "url": artifact.url,
                "checksum_type": artifact.checksum.name,
                "checksum_value": hex::encode(&artifact.checksum.value),
                "uses_wide_range": uses_wide_range,
                "lts_upper_bound_enforced": lts_upper_bound_enforced,
            })
        );
    } else {
        println!("No result");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEST_LTS_MAJOR_VERSION: i64 = 24;
    const ALLOW_WIDE_RANGE: bool = true;
    const DISALLOW_WIDE_RANGE: bool = false;

    #[test]
    fn parse_handles_latest() {
        let result = Requirement::from_str("latest");

        assert!(result.is_ok());
        if let Ok(reqs) = result {
            assert_eq!("*", reqs.to_string());
        }
    }

    #[test]
    fn parse_handles_exact_versions() {
        let result = Requirement::from_str("14.0.0");

        assert!(result.is_ok());
        if let Ok(reqs) = result {
            assert_eq!("14.0.0", reqs.to_string());
        }
    }

    #[test]
    fn parse_handles_starts_with_v() {
        let result = Requirement::from_str("v14.0.0");

        assert!(result.is_ok());
        if let Ok(reqs) = result {
            assert_eq!("14.0.0", reqs.to_string());
        }
    }

    #[test]
    fn parse_handles_semver_semantics() {
        let result = Requirement::from_str(">= 12.0.0");

        assert!(result.is_ok());
        if let Ok(reqs) = result {
            assert_eq!(">=12.0.0", reqs.to_string());
        }
    }

    #[test]
    fn parse_handles_pipe_statements() {
        let result = Requirement::from_str("^12 || ^13 || ^14");

        assert!(result.is_ok());
        if let Ok(reqs) = result {
            assert_eq!(
                ">=12.0.0 <13.0.0-0||>=13.0.0 <14.0.0-0||>=14.0.0 <15.0.0-0",
                reqs.to_string()
            );
        }
    }

    #[test]
    fn parse_handles_tilde_with_equals() {
        let result = Requirement::from_str("~=14.4");

        assert!(result.is_ok());
        if let Ok(reqs) = result {
            assert_eq!(">=14.4.0 <14.5.0-0", reqs.to_string());
        }
    }

    #[test]
    fn parse_handles_tilde_with_equals_and_patch() {
        let result = Requirement::from_str("~=14.4.3");

        assert!(result.is_ok());
        if let Ok(reqs) = result {
            assert_eq!(">=14.4.3 <14.5.0-0", reqs.to_string());
        }
    }

    #[test]
    fn parse_handles_v_within_string() {
        let result = Requirement::from_str(">v15.5.0");

        assert!(result.is_ok());
        if let Ok(reqs) = result {
            assert_eq!(">15.5.0", reqs.to_string());
        }
    }

    #[test]
    fn parse_handles_v_with_space() {
        let result = Requirement::from_str(">= v10.0.0");

        assert!(result.is_ok());
        if let Ok(reqs) = result {
            assert_eq!(">=10.0.0", reqs.to_string());
        }
    }

    #[test]
    fn parse_handles_equal_with_v() {
        let result = Requirement::from_str("=v10.22.0");

        assert!(result.is_ok());
        if let Ok(reqs) = result {
            assert_eq!("10.22.0", reqs.to_string());
        }
    }

    #[test]
    fn parse_returns_error_for_invalid_reqs() {
        let result = Requirement::from_str("12.%");
        assert!(result.is_err());
    }

    #[test]
    fn resolve_version_when_wide_range_used_and_version_is_downgraded_to_lts() {
        let wide_requirement = Requirement::from_str(">= 22").unwrap();
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
        assert_eq!(artifact.version.major, 24);
        assert!(*show_wide_range_warning);
        assert!(*show_downgrade_warning);
    }

    #[test]
    fn resolve_version_when_narrow_range_used_and_version_is_not_downgraded_to_lts() {
        let wide_requirement = Requirement::from_str("22.x").unwrap();
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
        assert_eq!(artifact.version.major, 22);
        assert!(!*show_wide_range_warning);
        assert!(!*show_downgrade_warning);
    }

    #[test]
    fn resolve_version_when_exact_range_used_and_version_is_not_downgraded_to_lts() {
        let wide_requirement = Requirement::from_str("22.21.0").unwrap();
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
        assert_eq!(artifact.version.major, 22);
        assert!(!*show_wide_range_warning);
        assert!(!*show_downgrade_warning);
    }

    #[test]
    fn resolve_version_when_wide_range_used_and_version_is_lts() {
        let wide_requirement = Requirement::from_str(">= 24").unwrap();
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
        assert_eq!(artifact.version.major, 24);
        assert!(*show_wide_range_warning);
        assert!(*show_downgrade_warning);
    }

    #[test]
    fn resolve_version_when_narrow_range_used_and_version_is_lts() {
        let wide_requirement = Requirement::from_str("24.x").unwrap();
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
        assert_eq!(artifact.version.major, 24);
        assert!(!*show_wide_range_warning);
        assert!(!*show_downgrade_warning);
    }

    #[test]
    fn resolve_version_when_exact_lts_range_used() {
        let wide_requirement = Requirement::from_str("24.10.0").unwrap();
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
        assert_eq!(artifact.version.major, 24);
        assert!(!*show_wide_range_warning);
        assert!(!*show_downgrade_warning);
    }

    #[test]
    fn resolve_version_when_wide_range_is_used_and_explicitly_requesting_range_beyond_lts() {
        let wide_requirement = Requirement::from_str(">=25.x").unwrap();
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
        assert_eq!(artifact.version.major, 25);
        assert!(*show_wide_range_warning);
        assert!(!*show_downgrade_warning);
    }

    #[test]
    fn resolve_version_when_narrow_range_is_used_and_explicitly_requesting_range_beyond_lts() {
        let wide_requirement = Requirement::from_str("25.x").unwrap();
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
        assert_eq!(artifact.version.major, 25);
        assert!(!*show_wide_range_warning);
        assert!(!*show_downgrade_warning);
    }

    #[test]
    fn resolve_version_when_exact_range_is_used_and_explicitly_requesting_range_beyond_lts() {
        let wide_requirement = Requirement::from_str("25.0.0").unwrap();
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
        assert_eq!(artifact.version.major, 25);
        assert!(!*show_wide_range_warning);
        assert!(!*show_downgrade_warning);
    }

    #[test]
    fn resolve_version_with_complex_range_with_upper_bound_within_lts() {
        let wide_requirement = Requirement::from_str(">=22.x <25.x").unwrap();
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
        assert_eq!(artifact.version.major, 24);
        assert!(*show_wide_range_warning);
        assert!(!*show_downgrade_warning);
    }

    #[test]
    fn resolve_version_with_complex_range_with_upper_bound_beyond_lts() {
        let wide_requirement = Requirement::from_str(">=25.x <27.x").unwrap();
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
        assert_eq!(artifact.version.major, 25);
        assert!(*show_wide_range_warning);
        assert!(!*show_downgrade_warning);
    }

    #[test]
    fn resolve_version_with_complex_range_with_lower_and_upper_bounds_within_lts() {
        let wide_requirement = Requirement::from_str(">=24.x <25.x").unwrap();
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
        assert_eq!(artifact.version.major, 24);
        assert!(!*show_wide_range_warning);
        assert!(!*show_downgrade_warning);
    }

    #[test]
    fn resolve_version_with_wide_range_environment_override_to_prevent_downgrade() {
        let wide_requirement = Requirement::from_str(">=22.x").unwrap();
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
        assert_eq!(artifact.version.major, 25);
        assert!(*show_wide_range_warning);
        assert!(!*show_downgrade_warning);
    }

    fn create_inventory() -> NodeInventory {
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
        NodeInventory::from_str(contents).unwrap()
    }
}
