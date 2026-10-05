# The migration is complete: every tracked shell script is linted (shellcheck enable=all) and
# formatted (tabs). There is no longer an allowlist. Build-time bin/lib scripts adopt
# namespace::function naming and the strict-mode/error-handling framework; runtime profile and
# support/test scripts are lint/format-only. shfmt -f discovers shell scripts by extension and
# shebang (so it catches the extensionless bin/ and test/ runners). test/shunit2 is vendored
# (upstream shUnit2) and is the sole exclusion.
# bash for `set -o pipefail` in the test targets, so `docker run ... | sed` fails when the tests fail.
SHELL := bash

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

# Opt-in caching proxy for registry.npmjs.org, registry.yarnpkg.com, and nodejs.org downloads.
# Start it with `make download-cache-start`, then run suites with `DOWNLOAD_CACHE=1`, e.g.
# `make DOWNLOAD_CACHE=1 heroku-24-npm`. The cache persists in DOWNLOAD_CACHE_DIR between runs.
DOWNLOAD_CACHE_DIR ?= $(HOME)/.cache/heroku-buildpack-nodejs/download-cache
DOWNLOAD_CACHE_CONTAINER := heroku-buildpack-nodejs-download-cache
DOWNLOAD_CACHE_HOSTS := registry.npmjs.org registry.yarnpkg.com nodejs.org

ifdef DOWNLOAD_CACHE
DOWNLOAD_CACHE_IP = $(shell docker inspect -f '{{.NetworkSettings.Networks.bridge.IPAddress}}' $(DOWNLOAD_CACHE_CONTAINER))
DOWNLOAD_CACHE_ARGS = $(foreach host,$(DOWNLOAD_CACHE_HOSTS),--add-host $(host):$(DOWNLOAD_CACHE_IP)) \
	-v $(DOWNLOAD_CACHE_DIR)/certs/ca.pem:/etc/download-cache-ca.pem:ro \
	-e NODE_EXTRA_CA_CERTS=/etc/download-cache-ca.pem \
	-e CURL_CA_BUNDLE=/tmp/ca-bundle.pem \
	-e SSL_CERT_FILE=/tmp/ca-bundle.pem \
	-e NPM_CONFIG_CAFILE=/tmp/ca-bundle.pem
DOWNLOAD_CACHE_SETUP = cat /etc/ssl/certs/ca-certificates.crt /etc/download-cache-ca.pem > /tmp/ca-bundle.pem; 
endif

.PHONY: download-cache-start download-cache-stop

download-cache-start:
	@[ -f "$(DOWNLOAD_CACHE_DIR)/certs/ca.pem" ] || bash test/download-cache/generate-certs.sh "$(DOWNLOAD_CACHE_DIR)/certs"
	@mkdir -p "$(DOWNLOAD_CACHE_DIR)/nginx"
	@docker run -d --rm --name $(DOWNLOAD_CACHE_CONTAINER) \
		-v $(CURDIR)/test/download-cache/nginx.conf:/etc/nginx/nginx.conf:ro \
		-v $(DOWNLOAD_CACHE_DIR)/certs:/certs:ro \
		-v $(DOWNLOAD_CACHE_DIR)/nginx:/cache \
		nginx:stable-alpine >/dev/null

download-cache-stop:
	@docker stop $(DOWNLOAD_CACHE_CONTAINER) >/dev/null

test: heroku-22-build heroku-24-build heroku-26-build

# Use `make -j4 heroku-26-build` to run all suites in parallel.
# Ctrl-C cleanly terminates all parallel jobs when using make -j.
heroku-26-build: heroku-26-npm heroku-26-yarn heroku-26-pnpm heroku-26-general
	@true

heroku-26-%:
	@set -o pipefail; docker run --platform "linux/amd64" -v $(shell pwd):/buildpack:ro --rm $(DOWNLOAD_CACHE_ARGS) -e "BUILDPACK_TEST_CURL_MAX_TIME=300" -e "BUILDPACK_TEST_CURL_CONNECT_TIMEOUT=30" -e "STACK=heroku-26" heroku/heroku:26-build bash -c "$(DOWNLOAD_CACHE_SETUP)cp -r /buildpack ~/buildpack_test; cd ~/buildpack_test/; test/run-$* $(if $(TEST),-- $(TEST),);" 2>&1 | sed "s/^/[heroku-26:$*] /"

# Use `make -j4 heroku-24-build` to run all suites in parallel.
# Ctrl-C cleanly terminates all parallel jobs when using make -j.
heroku-24-build: heroku-24-npm heroku-24-yarn heroku-24-pnpm heroku-24-general
	@true

heroku-24-%:
	@set -o pipefail; docker run --platform "linux/amd64" -v $(shell pwd):/buildpack:ro --rm $(DOWNLOAD_CACHE_ARGS) -e "BUILDPACK_TEST_CURL_MAX_TIME=300" -e "BUILDPACK_TEST_CURL_CONNECT_TIMEOUT=30" -e "STACK=heroku-24" heroku/heroku:24-build bash -c "$(DOWNLOAD_CACHE_SETUP)cp -r /buildpack ~/buildpack_test; cd ~/buildpack_test/; test/run-$* $(if $(TEST),-- $(TEST),);" 2>&1 | sed "s/^/[heroku-24:$*] /"

heroku-22-build: heroku-22-npm heroku-22-yarn heroku-22-pnpm heroku-22-general
	@true

heroku-22-%:
	@set -o pipefail; docker run -v $(shell pwd):/buildpack:ro --rm $(DOWNLOAD_CACHE_ARGS) -e "BUILDPACK_TEST_CURL_MAX_TIME=300" -e "BUILDPACK_TEST_CURL_CONNECT_TIMEOUT=30" -e "STACK=heroku-22" heroku/heroku:22-build bash -c "$(DOWNLOAD_CACHE_SETUP)cp -r /buildpack /buildpack_test; cd /buildpack_test/; test/run-$* $(if $(TEST),-- $(TEST),);" 2>&1 | sed "s/^/[heroku-22:$*] /"

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
