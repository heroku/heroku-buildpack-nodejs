use clap::{Parser, Subcommand};
use libherokubuildpack::inventory::artifact::{Arch, Os};
use nodejs_data::{
    NodejsInventoryWithSchedule, REJECTED_VERSIONS, VersionRange, active_lts_version,
    current_version, eol_date_for_version, is_wide_range, lts_upper_bound,
    maintenance_lts_versions,
};
use std::env::consts;

const VERSION_REQS_EXIT_CODE: i32 = 1;
const INVENTORY_EXIT_CODE: i32 = 2;
const UNSUPPORTED_OS_EXIT_CODE: i32 = 3;
const UNSUPPORTED_ARCH_EXIT_CODE: i32 = 4;

#[derive(Parser)]
#[command(name = "nodejs-data-query")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Output supported Node.js version information as JSON
    SupportedVersions { inventory_path: String },
    /// Resolve a Node.js version from the inventory
    ResolveVersion {
        inventory_path: String,
        node_version: String,
        #[arg(long)]
        os: Option<Os>,
        #[arg(long)]
        arch: Option<Arch>,
    },
}

fn load_inventory(path: &str) -> NodejsInventoryWithSchedule {
    let contents = std::fs::read_to_string(path).unwrap_or_else(|e| {
        eprintln!("Error reading '{path}': {e}");
        std::process::exit(INVENTORY_EXIT_CODE);
    });
    toml::from_str(&contents).unwrap_or_else(|e| {
        eprintln!("Error parsing '{path}': {e}");
        std::process::exit(INVENTORY_EXIT_CODE);
    })
}

fn resolve_os(os: Option<Os>) -> Os {
    os.unwrap_or_else(|| {
        consts::OS.parse::<Os>().unwrap_or_else(|e| {
            eprintln!("Unsupported OS '{}': {e}", consts::OS);
            std::process::exit(UNSUPPORTED_OS_EXIT_CODE);
        })
    })
}

fn resolve_arch(arch: Option<Arch>) -> Arch {
    arch.unwrap_or_else(|| {
        consts::ARCH.parse::<Arch>().unwrap_or_else(|e| {
            eprintln!("Unsupported Architecture '{}': {e}", consts::ARCH);
            std::process::exit(UNSUPPORTED_ARCH_EXIT_CODE);
        })
    })
}

fn should_enforce_lts_upper_bound(
    requirement: &VersionRange,
    inventory: &NodejsInventoryWithSchedule,
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
    inventory: &NodejsInventoryWithSchedule,
) -> VersionRange {
    if lts_upper_bound_enforced {
        let lts_major = active_lts_version(&inventory.schedule);
        VersionRange::parse(&format!("{lts_major}.x")).expect("LTS range should be valid")
    } else {
        requirement
    }
}

fn fail_unsupported_version(version: &nodejs_data::Version) -> bool {
    REJECTED_VERSIONS.contains(&version.major())
}

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Commands::SupportedVersions { inventory_path } => {
            let inventory = load_inventory(&inventory_path);
            let current = current_version(&inventory.schedule);
            let active_lts = active_lts_version(&inventory.schedule);
            let maintenance_lts = maintenance_lts_versions(&inventory.schedule);
            println!(
                "{}",
                serde_json::json!({
                    "current": current,
                    "active_lts": active_lts,
                    "maintenance_lts": maintenance_lts,
                })
            );
        }
        Commands::ResolveVersion {
            inventory_path,
            node_version,
            os,
            arch,
        } => {
            let allow_wide_range = std::env::var("NODEJS_ALLOW_WIDE_RANGE")
                .map(|val| val == "true")
                .unwrap_or(false);

            let inventory = load_inventory(&inventory_path);
            let os = resolve_os(os);
            let arch = resolve_arch(arch);

            let requirement = VersionRange::parse(node_version.as_str()).unwrap_or_else(|e| {
                eprintln!("Could not parse Version Requirements '{node_version}': {e}");
                std::process::exit(VERSION_REQS_EXIT_CODE);
            });

            let uses_wide_range = is_wide_range(&requirement, &inventory);

            let lts_upper_bound_enforced = !allow_wide_range
                && should_enforce_lts_upper_bound(&requirement, &inventory, os, arch);

            let requirement =
                effective_requirement(requirement, lts_upper_bound_enforced, &inventory);

            if let Some(artifact) = inventory.inventory.resolve(os, arch, &requirement) {
                let eol = eol_date_for_version(&artifact.version, &inventory);
                let fail_build = fail_unsupported_version(&artifact.version);
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
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn load_test_inventory() -> NodejsInventoryWithSchedule {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../inventory/node.toml");
        let contents = std::fs::read_to_string(&path).expect("should read inventory file");
        toml::from_str(&contents).expect("should parse inventory")
    }

    #[test]
    fn enforce_lts_when_resolved_version_exceeds_lts() {
        let inventory = load_test_inventory();
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
        let inventory = load_test_inventory();
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
        let inventory = load_test_inventory();
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
        let inventory = load_test_inventory();
        let requirement = VersionRange::parse(">= 22").unwrap();
        let result = effective_requirement(requirement, true, &inventory);
        assert_eq!(result.to_string(), "24.x");
    }

    #[test]
    fn effective_requirement_returns_original_when_not_enforced() {
        let requirement = VersionRange::parse(">= 22").unwrap();
        let inventory = load_test_inventory();
        let result = effective_requirement(requirement, false, &inventory);
        assert_eq!(result.to_string(), ">= 22");
    }

    #[test]
    fn supported_versions_output_structure() {
        let inventory = load_test_inventory();
        let current = current_version(&inventory.schedule);
        let active_lts = active_lts_version(&inventory.schedule);
        let maintenance_lts = maintenance_lts_versions(&inventory.schedule);

        assert!(current > 0);
        assert!(active_lts > 0);
        assert!(current > active_lts);
        assert!(!maintenance_lts.is_empty());
        for v in &maintenance_lts {
            assert!(*v < active_lts);
        }
    }
}
