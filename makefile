build-resolvers: build-resolver-linux

.build:
	mkdir -p .build

build-resolver-linux: .build
	CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER="$(shell which x86_64-unknown-linux-musl-gcc)" \
	    CC_X86_64_UNKNOWN_LINUX_MUSL="$(shell which x86_64-unknown-linux-musl-gcc)" \
	    cargo build --manifest-path ./resolve-version/Cargo.toml --target x86_64-unknown-linux-musl --profile release
	mv ./resolve-version/target/x86_64-unknown-linux-musl/release/resolve-version lib/vendor/resolve-version-linux

test: heroku-22-build heroku-24-build

shellcheck:
	@shellcheck -x bin/compile bin/detect bin/release bin/test bin/test-compile
	@shellcheck -x lib/*.sh
	@shellcheck -x ci-profile/**
	@shellcheck -x etc/**

heroku-24-build:
	@echo "Running tests in docker (heroku-24-build)..."
	@docker run --platform "linux/amd64" -v $(shell pwd):/buildpack:ro --rm -it -e "STACK=heroku-24" heroku/heroku:24-build bash -c 'cp -r /buildpack ~/buildpack_test; cd ~/buildpack_test/; test/run;'
	@echo ""

heroku-22-build:
	@echo "Running tests in docker (heroku-22-build)..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it -e "STACK=heroku-22" heroku/heroku:22-build bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; test/run;'
	@echo ""

hatchet:
	@echo "Running hatchet integration tests..."
	@bash etc/ci-setup.sh
	@bash etc/hatchet.sh spec/ci/
	@echo ""

nodebin-test:
	@echo "Running test for Node v${TEST_NODE_VERSION}..."
	@bash etc/ci-setup.sh
	@bash etc/hatchet.sh spec/nodebin/
	@echo ""

unit:
	@echo "Running unit tests in docker (heroku-22)..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it -e "STACK=heroku-22" heroku/heroku:22 bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; test/unit;'
	@echo ""

shell:
	@echo "Opening heroku-22 shell..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it heroku/heroku:22 bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; bash'
	@echo ""
