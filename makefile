# The migration is complete: every tracked shell script is linted (shellcheck enable=all) and
# formatted (tabs). There is no longer an allowlist. Build-time bin/lib scripts adopt
# namespace::function naming and the strict-mode/error-handling framework; runtime profile and
# support/test scripts are lint/format-only. shfmt -f discovers shell scripts by extension and
# shebang (so it catches the extensionless bin/ and test/ runners). test/shunit2 is vendored
# (upstream shUnit2) and is the sole exclusion.
SHELL_FILES = $(shell shfmt -f bin ci-profile etc lib profile test | grep -v '^test/shunit2$$')

.PHONY: lint lint-scripts check-format format

lint: lint-scripts check-format

lint-scripts:
	shellcheck --check-sourced $(SHELL_FILES)

check-format:
	shfmt --diff $(SHELL_FILES)

format:
	shfmt --write --list $(SHELL_FILES)

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
