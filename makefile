build-resolvers: build-resolver-linux build-resolver-darwin build-resolver-linux-arm build-resolver-darwin-arm

.build:
	mkdir -p .build
build-resolver-darwin: .build
	cargo install heroku-nodejs-utils --root .build --bin resolve_version --git https://github.com/heroku/buildpacks-nodejs --target x86_64-apple-darwin --profile release
	mv .build/bin/resolve_version lib/vendor/resolve-version-darwin
	cp lib/vendor/resolve-version-darwin lib/vendor/resolve-version-darwin-x64

build-resolver-darwin-arm: .build
	cargo install heroku-nodejs-utils --root .build --bin resolve_version --git https://github.com/heroku/buildpacks-nodejs --target aarch64-apple-darwin --profile release
	mv .build/bin/resolve_version lib/vendor/resolve-version-darwin-arm

build-resolver-linux: .build
	cargo install heroku-nodejs-utils --root .build --bin resolve_version --git https://github.com/heroku/buildpacks-nodejs --target x86_64-unknown-linux-musl --profile release
	mv .build/bin/resolve_version lib/vendor/resolve-version-linux
	cp lib/vendor/resolve-version-linux lib/vendor/resolve-version-linux-x64

build-resolver-linux-arm: .build
	cargo install heroku-nodejs-utils --root .build --bin resolve_version --git https://github.com/heroku/buildpacks-nodejs --target aarch64-unknown-linux-musl --profile release
	mv .build/bin/resolve_version lib/vendor/resolve-version-linux-arm

test: heroku-22-build heroku-20-build heroku-24-build

test-binary:
	go test -v ./cmd/... -tags=integration

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

heroku-20-build:
	@echo "Running tests in docker (heroku-20-build)..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it -e "STACK=heroku-20" heroku/heroku:20-build bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; test/run;'
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
