test: heroku-18 heroku-16 cedar-14

build:
	@GOOS=darwin GOARCH=amd64 go build -ldflags="-s -w" -v -o ./vendor/resolve-version-darwin ./cmd/resolve-version
	@GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -v -o ./vendor/resolve-version-linux ./cmd/resolve-version

build-production:
	# build go binaries and then compress them
	@GOOS=darwin GOARCH=amd64 go build -ldflags="-s -w" -v -o ./vendor/resolve-version-darwin ./cmd/resolve-version
	@GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -v -o ./vendor/resolve-version-linux ./cmd/resolve-version
	# https://blog.filippo.io/shrink-your-go-binaries-with-this-one-weird-trick/
	upx --brute vendor/resolve-version-linux
	upx --brute vendor/resolve-version-darwin

test-binary:
	go test -v ./cmd/... -tags=integration

shellcheck:
	@shellcheck -x bin/compile bin/detect bin/release bin/test bin/test-compile
	@shellcheck -x lib/**
	@shellcheck -x ci-profile/**
	@shellcheck -x etc/**

heroku-18:
	@echo "Running tests in docker (heroku-18)..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it -e "STACK=heroku-18" heroku/heroku:18 bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; test/run;'
	@echo ""

heroku-16:
	@echo "Running tests in docker (heroku-16)..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it -e "STACK=heroku-16" heroku/heroku:16 bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; test/run;'
	@echo ""

cedar-14:
	@echo "Running tests in docker (cedar-14)..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it -e "STACK=cedar-14" heroku/cedar:14 bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; test/run;'
	@echo ""

hatchet:
	@echo "Running hatchet integration tests..."
	@bash etc/ci-setup.sh
	@bash etc/hatchet.sh spec/ci/
	@bash etc/ci-cleanup.sh
	@echo ""

nodebin-test:
	@echo "Running test for Node v${TEST_NODE_VERSION}..."
	@bash etc/ci-setup.sh
	@bash etc/hatchet.sh spec/nodebin/
	@echo ""

unit:
	@echo "Running unit tests in docker (heroku-18)..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it -e "STACK=heroku-18" heroku/heroku:18 bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; test/unit;'
	@echo ""

shell:
	@echo "Opening heroku-16 shell..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it heroku/heroku:16 bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; bash'
	@echo ""
