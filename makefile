BUILDDIR := $(PWD)/.build

build-resolvers: build-resolver-linux build-resolver-darwin

build-resolver-darwin: pull-cnb
	cd $(BUILDDIR)/buildpacks-nodejs; cargo build --bin resolve_version --target x86_64-apple-darwin --release
	mv $(BUILDDIR)/buildpacks-nodejs/target/x86_64-apple-darwin/release/resolve_version $(PWD)/lib/vendor/resolve-version-darwin

build-resolver-linux: pull-cnb
	cd $(BUILDDIR)/buildpacks-nodejs; cargo build --bin resolve_version --target x86_64-unknown-linux-musl --release
	mv $(BUILDDIR)/buildpacks-nodejs/target/x86_64-unknown-linux-musl/release/resolve_version $(PWD)/lib/vendor/resolve-version-linux

pull-cnb: $(BUILDDIR)/buildpacks-nodejs
	cd $(BUILDDIR)/buildpacks-nodejs; git pull

$(BUILDDIR)/buildpacks-nodejs:
	mkdir -p $(BUILDDIR)
	git clone git@github.com:heroku/buildpacks-nodejs $(BUILDDIR)/buildpacks-nodejs

test: heroku-22-build heroku-20-build heroku-18-build

test-binary:
	go test -v ./cmd/... -tags=integration

shellcheck:
	@shellcheck -x bin/compile bin/detect bin/release bin/test bin/test-compile
	@shellcheck -x lib/*.sh
	@shellcheck -x ci-profile/**
	@shellcheck -x etc/**

heroku-22-build:
	@echo "Running tests in docker (heroku-22-build)..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it -e "STACK=heroku-22" heroku/heroku:22-build bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; test/run;'
	@echo ""

heroku-20-build:
	@echo "Running tests in docker (heroku-20-build)..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it -e "STACK=heroku-20" heroku/heroku:20-build bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; test/run;'
	@echo ""

heroku-18-build:
	@echo "Running tests in docker (heroku-18-build)..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it -e "STACK=heroku-18" heroku/heroku:18-build bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; test/run;'
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
