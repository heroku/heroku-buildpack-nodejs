test: test-cedar-14 test-cedar-10

test-cedar-14:
	@echo "Running tests in docker (cedar-14)..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it heroku/cedar:14 bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; test/run;'
	@echo ""

test-cedar-10:
	@echo "Running tests in docker (cedar)..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it fabiokung/cedar bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; test/run;'

shell:
	@echo "Opening cedar-14 shell..."
	@docker run -v $(shell pwd):/buildpack:ro --rm -it heroku/cedar:14 bash -c 'cp -r /buildpack /buildpack_test; cd /buildpack_test/; bash'
	@echo ""
