use clap::{Command, arg, value_parser};
use libherokubuildpack::inventory::artifact::{Arch, Os};
use node_semver::{Range, SemverError, Version};
use sha2::Sha256;
use std::env::consts;
use std::str::FromStr;
use libherokubuildpack::inventory::version::VersionRequirement;

const VERSION_REQS_EXIT_CODE: i32 = 1;
const INVENTORY_EXIT_CODE: i32 = 2;
const UNSUPPORTED_OS_EXIT_CODE: i32 = 3;
const UNSUPPORTED_ARCH_EXIT_CODE: i32 = 4;

fn main() {
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

    let version_requirements = Requirement::from_str(node_version.as_str()).unwrap_or_else(|e| {
        eprintln!("Could not parse Version Requirements '{node_version}': {e}");
        std::process::exit(VERSION_REQS_EXIT_CODE);
    });

    let inv_contents = std::fs::read_to_string(inventory_path).unwrap_or_else(|e| {
        eprintln!("Error reading '{inventory_path}': {e}");
        std::process::exit(INVENTORY_EXIT_CODE);
    });

    let inv: libherokubuildpack::inventory::Inventory<Version, Sha256, Option<()>> =
        toml::from_str(&inv_contents).unwrap_or_else(|e| {
            eprintln!("Error parsing '{inventory_path}': {e}");
            std::process::exit(INVENTORY_EXIT_CODE);
        });

    let version = inv.resolve(os, arch, &version_requirements);

    if let Some(version) = version {
        println!(
            "{} {} {} {}",
            version.version,
            version.url,
            version.checksum.name,
            hex::encode(&version.checksum.value)
        );
    } else {
        println!("No result");
    }
}

pub struct Requirement(Range);

impl FromStr for Requirement {
    type Err = SemverError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        let value = value.trim();

        let value = if value.starts_with("~=") {
            value.replacen('=', "", 1)
        } else {
            value.to_string()
        };

        if value == "latest" {
            Ok(Requirement(Range::any()))
        } else {
            Range::parse(value).map(Self)
        }
    }
}

impl std::fmt::Display for Requirement {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl VersionRequirement<Version> for Requirement {
    fn satisfies(&self, version: &Version) -> bool {
        self.0.satisfies(version)
    }
}


#[cfg(test)]
mod tests {
    use super::*;

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
}
