use clap::{Command, arg, value_parser};
use libherokubuildpack::inventory::artifact::{Arch, Os};
use nodejs_data::{
    NodejsInventoryWithMetadata, VersionRange, eol_date_for_version, fail_unsupported_version,
    is_wide_range, lts_upper_bound,
};
use std::env::consts;

const VERSION_REQS_EXIT_CODE: i32 = 1;
const INVENTORY_EXIT_CODE: i32 = 2;
const UNSUPPORTED_OS_EXIT_CODE: i32 = 3;
const UNSUPPORTED_ARCH_EXIT_CODE: i32 = 4;

fn should_enforce_lts_upper_bound(
    requirement: &VersionRange,
    inventory: &NodejsInventoryWithMetadata,
    os: Os,
    arch: Arch,
) -> bool {
    if let Some(lts_version) = lts_upper_bound(requirement, inventory) {
        inventory
            .inventory
            .resolve(os, arch, requirement)
            .is_some_and(|resolved| resolved.version > lts_version)
    } else {
        false
    }
}

fn effective_requirement(
    requirement: VersionRange,
    lts_upper_bound_enforced: bool,
    inventory: &NodejsInventoryWithMetadata,
) -> VersionRange {
    if lts_upper_bound_enforced {
        VersionRange::parse(&format!("{}.x", inventory.metadata.active_lts_version))
            .expect("LTS range should be valid")
    } else {
        requirement
    }
}

fn main() {
    let allow_wide_range = std::env::var("NODEJS_ALLOW_WIDE_RANGE")
        .map(|val| val == "true")
        .unwrap_or(false);

    let matches = Command::new("resolve_version")
        .arg(arg!(<inventory_path>))
        .arg(arg!(<node_version>))
        // lts_major_version is still accepted for backwards compat but ignored;
        // we use inventory.metadata.active_lts_version instead.
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

    let inventory: NodejsInventoryWithMetadata =
        toml::from_str(&inventory_contents).unwrap_or_else(|e| {
            eprintln!("Error parsing '{inventory_path}': {e}");
            std::process::exit(INVENTORY_EXIT_CODE);
        });

    let uses_wide_range = is_wide_range(&requirement, &inventory);

    let lts_upper_bound_enforced =
        !allow_wide_range && should_enforce_lts_upper_bound(&requirement, &inventory, os, arch);

    let requirement = effective_requirement(requirement, lts_upper_bound_enforced, &inventory);

    if let Some(artifact) = inventory.inventory.resolve(os, arch, &requirement) {
        let eol = eol_date_for_version(&artifact.version, &inventory);
        let fail_build = fail_unsupported_version(&artifact.version, &inventory);
        println!(
            "{}",
            serde_json::json!({
                "version": artifact.version,
                "url": artifact.url,
                "checksum_type": artifact.checksum.name,
                "checksum_value": hex::encode(&artifact.checksum.value),
                "uses_wide_range": uses_wide_range,
                "lts_upper_bound_enforced": lts_upper_bound_enforced,
                "eol_date": eol.to_string(),
                "fail_build": fail_build,
            })
        );
    } else {
        println!("No result");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn enforce_lts_when_resolved_version_exceeds_lts() {
        let inventory = load_inventory();
        let requirement = VersionRange::parse(">= 22").unwrap();
        assert!(should_enforce_lts_upper_bound(
            &requirement,
            &inventory,
            Os::Linux,
            Arch::Amd64
        ));
    }

    #[test]
    fn no_enforce_lts_when_range_starts_above_lts() {
        let inventory = load_inventory();
        let requirement = VersionRange::parse(">=25.x").unwrap();
        assert!(!should_enforce_lts_upper_bound(
            &requirement,
            &inventory,
            Os::Linux,
            Arch::Amd64
        ));
    }

    #[test]
    fn no_enforce_lts_when_narrow_range_within_lts() {
        let inventory = load_inventory();
        let requirement = VersionRange::parse("24.x").unwrap();
        assert!(!should_enforce_lts_upper_bound(
            &requirement,
            &inventory,
            Os::Linux,
            Arch::Amd64
        ));
    }

    #[test]
    fn effective_requirement_returns_lts_range_when_enforced() {
        let inventory = load_inventory();
        let requirement = VersionRange::parse(">= 22").unwrap();
        let result = effective_requirement(requirement, true, &inventory);
        assert_eq!(result.to_string(), "24.x");
    }

    #[test]
    fn effective_requirement_returns_original_when_not_enforced() {
        let inventory = load_inventory();
        let requirement = VersionRange::parse(">= 22").unwrap();
        let result = effective_requirement(requirement, false, &inventory);
        assert_eq!(result.to_string(), ">= 22");
    }

    fn load_inventory() -> NodejsInventoryWithMetadata {
        let inventory_path =
            std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../inventory/node.toml");
        let contents =
            std::fs::read_to_string(&inventory_path).expect("should read inventory file");
        toml::from_str(&contents).expect("should parse inventory")
    }
}
