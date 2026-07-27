# Contributing

Thanks for making a contribution to the Heroku Node.js Buildpack!

*Note: If you are looking to open an issue or make a contribution to the Heroku Node.js Cloud Native Buildpacks (this includes builds made with `pack`), go here: https://github.com/heroku/buildpacks-nodejs*

## Prerequisites

For local development, you may need the following tools:

- [Docker](https://docs.docker.com/engine/install/) (required to run the test suite)
- [Rust](https://www.rust-lang.org/tools/install) (for building the version resolver in `resolve-version/`)
- The `x86_64-unknown-linux-musl` cross-compilation target and linker (used by `make build-resolvers`)

## Clone the repo

Fork and clone the repository:

```sh
git clone git@github.com:your-username/heroku-buildpack-nodejs.git
```

## Deploying an app with a fork or branch

Push your changes to your fork, then create a new Heroku app to test it, or configure an existing app to use your buildpack:

```sh
# Create a new Heroku app that uses your buildpack
heroku create --buildpack <your-github-url>

# Configure an existing Heroku app to use your buildpack
heroku buildpacks:set <your-github-url>

# You can also use a git branch!
heroku buildpacks:set <your-github-url>#your-branch
```

## Testing

The tests use [Docker](https://www.docker.com/) to simulate Heroku's stacks, and run via the vendored [shunit2](https://github.com/kward/shunit2) test framework.

For any change you make, write a unit test in `test/run` that would break if you removed the code you've just worked on. Add a fixture (`test/fixtures/*`) if you need an additional sample app to test with.

Run the full test suite:

```sh
make test
```

Test a single stack (usually adequate):

```sh
make heroku-22-build
make heroku-24-build
make heroku-26-build
```

Run just the unit tests:

```sh
make unit
```

Lint and check formatting of the shell scripts:

```sh
make lint
```

## Opening a Pull Request

After the work is completed, please open a pull request. If it links to an Issue, include it in the description:

```md
Fixes: https://github.com/heroku/heroku-buildpack-nodejs/issues/xxx
```

Also add an explanation of the work done and the tests included.
