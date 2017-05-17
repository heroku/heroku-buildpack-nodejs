test: test-heroku-16 test-cedar-14

test-heroku-16:
	@echo "Running tests in docker (heroku-16)..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it -e "STACK=heroku-16" heroku/heroku:16 bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; test/run;'
	@echo ""

test-cedar-14:
	@echo "Running tests in docker (cedar-14)..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it -e "STACK=cedar-14" heroku/cedar:14 bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; test/run;'
	@echo ""

shell:
	@echo "Opening heroku-16 shell..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it heroku/heroku:16 bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; bash'
	@echo ""
