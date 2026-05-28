# Coverage spike — see docs/superpowers/specs/2026-05-27-bash-coverage-spike-design.md
COVERAGE_DIR := $(shell pwd)/coverage/traces
COV_DOCKER_ARGS = $(if $(BUILDPACK_COVERAGE),-v $(COVERAGE_DIR):/coverage -e BUILDPACK_COVERAGE=1 -e BUILDPACK_COVERAGE_DIR=/coverage,)

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

shellcheck:
	@shellcheck -x bin/compile bin/detect bin/release bin/test bin/test-compile
	@shellcheck -x lib/*.sh
	@shellcheck -x ci-profile/**
	@shellcheck -x etc/**

# Use `make -j4 heroku-26-build` to run all suites in parallel.
# Ctrl-C cleanly terminates all parallel jobs when using make -j.
heroku-26-build: heroku-26-npm heroku-26-yarn heroku-26-pnpm heroku-26-general
	@true

heroku-26-%:
	@mkdir -p $(COVERAGE_DIR)
	@docker run --platform "linux/amd64" -v $(shell pwd):/buildpack:ro $(COV_DOCKER_ARGS) --rm -e "STACK=heroku-26" heroku/heroku:26-build bash -c "cp -r /buildpack ~/buildpack_test; cd ~/buildpack_test/; test/run-$* $(if $(TEST),-- $(TEST),);" 2>&1 | sed "s/^/[heroku-26:$*] /"

# Use `make -j4 heroku-24-build` to run all suites in parallel.
# Ctrl-C cleanly terminates all parallel jobs when using make -j.
heroku-24-build: heroku-24-npm heroku-24-yarn heroku-24-pnpm heroku-24-general
	@true

heroku-24-%:
	@mkdir -p $(COVERAGE_DIR)
	@docker run --platform "linux/amd64" -v $(shell pwd):/buildpack:ro $(COV_DOCKER_ARGS) --rm -e "STACK=heroku-24" heroku/heroku:24-build bash -c "cp -r /buildpack ~/buildpack_test; cd ~/buildpack_test/; test/run-$* $(if $(TEST),-- $(TEST),);" 2>&1 | sed "s/^/[heroku-24:$*] /"

heroku-22-build: heroku-22-npm heroku-22-yarn heroku-22-pnpm heroku-22-general
	@true

heroku-22-%:
	@mkdir -p $(COVERAGE_DIR)
	@docker run -v $(shell pwd):/buildpack:ro $(COV_DOCKER_ARGS) --rm -e "STACK=heroku-22" heroku/heroku:22-build bash -c "cp -r /buildpack /buildpack_test; cd /buildpack_test/; test/run-$* $(if $(TEST),-- $(TEST),);" 2>&1 | sed "s/^/[heroku-22:$*] /"

hatchet:
	@echo "Running hatchet integration tests..."
	@bash etc/ci-setup.sh
	@bash etc/hatchet.sh spec/ci/
	@echo ""

unit:
	@echo "Running unit tests in docker (heroku-22)..."
	@mkdir -p $(COVERAGE_DIR)
	@docker run -v $(shell pwd):/buildpack:ro $(COV_DOCKER_ARGS) --rm -it -e "STACK=heroku-22" heroku/heroku:22 bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; test/unit;'
	@echo ""

shell:
	@echo "Opening heroku-22 shell..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it heroku/heroku:22 bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; bash'
	@echo ""

.PHONY: coverage
coverage:
	@echo "==> Coverage spike: clearing previous output"
	@rm -rf coverage
	@mkdir -p $(COVERAGE_DIR)
	@echo "==> Running unit tests with coverage"
	@BUILDPACK_COVERAGE=1 $(MAKE) unit
	@echo "==> Running heroku-26 functional tests with coverage"
	@BUILDPACK_COVERAGE=1 $(MAKE) heroku-26-build
	@echo "==> Running hatchet integration tests with coverage"
	@CI=true BUILDPACK_COVERAGE=1 $(MAKE) hatchet
	@echo "==> Generating coverage report"
	@BUILDPACK_REPO_ROOT=$(shell pwd) bundle exec ruby etc/generate-coverage-report
	@echo "==> Done. Open coverage/index.html"
