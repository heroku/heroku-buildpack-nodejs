# Files migrated to tabs + shellcheck enable=all + namespace::function naming.
# Add a file here only once it passes `make lint` cleanly. This list is the single
# source of truth for what gets linted/formatted (CI invokes these targets, it does
# not maintain its own list).
MIGRATED_FILES = \
	lib/failures.sh \
	lib/package_managers/npm.sh \
	lib/package_managers/pnpm.sh \
	lib/runtimes/nodejs.sh

.PHONY: lint lint-scripts check-format format

lint: lint-scripts check-format

lint-scripts:
	@if [ -n "$(strip $(MIGRATED_FILES))" ]; then \
		shellcheck --check-sourced $(MIGRATED_FILES); \
	else \
		echo "lint-scripts: no migrated files yet"; \
	fi

check-format:
	@if [ -n "$(strip $(MIGRATED_FILES))" ]; then \
		shfmt --diff $(MIGRATED_FILES); \
	else \
		echo "check-format: no migrated files yet"; \
	fi

format:
	@if [ -n "$(strip $(MIGRATED_FILES))" ]; then \
		shfmt --write --list $(MIGRATED_FILES); \
	else \
		echo "format: no migrated files yet"; \
	fi

build-resolvers: build-resolver-linux

.build:
	mkdir -p .build

build-resolver-linux: .build
	@cargo test --manifest-path ./resolve-version/Cargo.toml
	CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER="$(shell which x86_64-unknown-linux-musl-gcc)" \
	    CC_X86_64_UNKNOWN_LINUX_MUSL="$(shell which x86_64-unknown-linux-musl-gcc)" \
	    cargo build --manifest-path ./resolve-version/Cargo.toml --target x86_64-unknown-linux-musl --profile release
	mv ./resolve-version/target/x86_64-unknown-linux-musl/release/resolve-version lib/vendor/resolve-version-linux

test: heroku-22-build heroku-24-build heroku-26-build

# Use `make -j4 heroku-26-build` to run all suites in parallel.
# Ctrl-C cleanly terminates all parallel jobs when using make -j.
heroku-26-build: heroku-26-npm heroku-26-yarn heroku-26-pnpm heroku-26-general
	@true

heroku-26-%:
	@docker run --platform "linux/amd64" -v $(shell pwd):/buildpack:ro --rm -e "STACK=heroku-26" heroku/heroku:26-build bash -c "cp -r /buildpack ~/buildpack_test; cd ~/buildpack_test/; test/run-$* $(if $(TEST),-- $(TEST),);" 2>&1 | sed "s/^/[heroku-26:$*] /"

# Use `make -j4 heroku-24-build` to run all suites in parallel.
# Ctrl-C cleanly terminates all parallel jobs when using make -j.
heroku-24-build: heroku-24-npm heroku-24-yarn heroku-24-pnpm heroku-24-general
	@true

heroku-24-%:
	@docker run --platform "linux/amd64" -v $(shell pwd):/buildpack:ro --rm -e "STACK=heroku-24" heroku/heroku:24-build bash -c "cp -r /buildpack ~/buildpack_test; cd ~/buildpack_test/; test/run-$* $(if $(TEST),-- $(TEST),);" 2>&1 | sed "s/^/[heroku-24:$*] /"

heroku-22-build: heroku-22-npm heroku-22-yarn heroku-22-pnpm heroku-22-general
	@true

heroku-22-%:
	@docker run -v $(shell pwd):/buildpack:ro --rm -e "STACK=heroku-22" heroku/heroku:22-build bash -c "cp -r /buildpack /buildpack_test; cd /buildpack_test/; test/run-$* $(if $(TEST),-- $(TEST),);" 2>&1 | sed "s/^/[heroku-22:$*] /"

hatchet:
	@echo "Running hatchet integration tests..."
	@bash etc/ci-setup.sh
	@bash etc/hatchet.sh spec/ci/
	@echo ""

unit:
	@echo "Running unit tests in docker (heroku-22)..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it -e "STACK=heroku-22" heroku/heroku:22 bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; test/unit;'
	@echo ""

shell:
	@echo "Opening heroku-22 shell..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it heroku/heroku:22 bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; bash'
	@echo ""
