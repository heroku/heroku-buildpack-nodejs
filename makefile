test: test-heroku-18 test-heroku-16 test-cedar-14

test-heroku-18:
	docker pull "heroku/heroku-18"
	@echo "Running tests in docker (heroku-18)..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it -e "STACK=heroku-18" heroku/heroku:18 bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; test/run;'
	@echo ""

test-heroku-16:
	docker pull "heroku/heroku-16"
	@echo "Running tests in docker (heroku-16)..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it -e "STACK=heroku-16" heroku/heroku:16 bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; test/run;'
	@echo ""

test-cedar-14:
	docker pull "heroku/cedar-14"
	@echo "Running tests in docker (cedar-14)..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it -e "STACK=cedar-14" heroku/cedar:14 bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; test/run;'
	@echo ""

test-hatchet:
	@echo "Running hatchet integration tests"
	bash etc/ci-setup.sh
	bash etc/hatchet.sh spec/
	@echo ""

shell:
	@echo "Opening heroku-16 shell..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it heroku/heroku:16 bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; bash'
	@echo ""
