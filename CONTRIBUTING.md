# Contributing

Thanks for making a contribution to the Heroku Node.js Buildpack!

*Note: If you are looking to open an issue or make a contribution to the Heroku Node.js Cloud Native Buildpacks (this includes builds made with `pack`), go here: https://github.com/heroku/nodejs-engine-buildpack*

## Setup

### Install Docker (optional)

Before you get started, you may want to [install Docker](https://docs.docker.com/engine/install/). Docker will be needed to run the test suite.

If you don't install Docker, you have the option of waiting until your pull request open to run tests. [The Travis tests can be found here.](https://travis-ci.com/github/heroku/heroku-buildpack-nodejs/pull_requests)

### Clone Repo

First, you will want to fork and clone the repository.

```sh
git clone git@github.com:your-username/heroku-buildpack-nodejs.git
```

Once you have this on your local machine, you're ready to start making changes.

## Testing

### Writing Tests

There are unit tests that are run with `shunit`. For any change you make, write a unit test in `test/run` that would break if you removed the code that you've just worked on. Add a fixture (`test/fixtures/*`) if you need an additional sample app to test with. [More info about testing here.](https://github.com/heroku/heroku-buildpack-nodejs#tests)

### Running Tests

To run the tests, run `make test`. You will need Docker installed. This will start a test run of all 3 Heroku stack images that will run serially. If you want to test one stack image (which is usually adequate), run `make heroku-22` (or whatever stack image you'd like to test).

## Opening a Pull Request

After the work is completed, please open a pull request. If it links to an Issue, please make sure to include in the Description:

```md
Fixes: https://github.com/heroku/heroku-buildpack-nodejs/issues/xxx
```

In the Description, also add an explanation of the work that's done and the tests that are included.
