# Heroku Buildpack for Node.js

![nodejs](https://raw.githubusercontent.com/heroku/buildpacks/refs/heads/main/assets/images/buildpack-banner-node-js.png)

This is the official [Heroku buildpack](http://devcenter.heroku.com/articles/buildpacks) for Node.js apps.

[![CI](https://github.com/heroku/heroku-buildpack-nodejs/actions/workflows/ci.yml/badge.svg)](https://github.com/heroku/heroku-buildpack-nodejs/actions/workflows/ci.yml)

## Documentation

For more information about using this Node.js buildpack on Heroku, see these Dev Center articles:

- [Heroku Node.js Support](https://devcenter.heroku.com/articles/nodejs-support)
- [Getting Started with Node.js on Heroku](https://devcenter.heroku.com/articles/nodejs)
- [Troubleshooting Node.js Deploys](https://devcenter.heroku.com/articles/troubleshooting-node-deploys)

For more general information about buildpacks on Heroku:

- [Buildpacks](https://devcenter.heroku.com/articles/buildpacks)
- [Buildpack API](https://devcenter.heroku.com/articles/buildpack-api)

## Using the Heroku Node.js buildpack

It's suggested that you use the latest version of the release buildpack. You can set it using the `heroku-cli`.

```sh
heroku buildpacks:set heroku/nodejs
```

Your builds will always use the latest published release of the buildpack.

> **Note:** `buildpacks:set` replaces the buildpack at position 1. If your app
> already uses other buildpacks, use `buildpacks:add --index 1 heroku/nodejs`
> instead so this one isn't overwritten. See
> [Managing Buildpacks](https://devcenter.heroku.com/articles/managing-buildpacks).

## Chain Node with multiple buildpacks

This buildpack automatically exports node, npm, and any node_modules binaries
into the `$PATH` for easy use in subsequent buildpacks.

## Feedback

Having trouble? Dig it? Feature request?

- [help.heroku.com](https://help.heroku.com/)
- [GitHub issues](https://github.com/heroku/heroku-buildpack-nodejs/issues)

## Development

### Prerequisites

For local development, you may need the following tools:

- [Docker](https://hub.docker.com/search?type=edition&offering=community)
- [Rust](https://www.rust-lang.org/tools/install) (for building the version resolver in `resolve-version/`)
- The `x86_64-unknown-linux-musl` cross-compilation target and linker (used by `make build-resolvers`)

### Deploying an app with a fork or branch

To make changes to this buildpack, fork it on GitHub.
Push up changes to your fork, then create a new Heroku app to test it,
or configure an existing app to use your buildpack:

```
# Create a new Heroku app that uses your buildpack
heroku create --buildpack <your-github-url>

# Configure an existing Heroku app to use your buildpack
heroku buildpacks:set <your-github-url>

# You can also use a git branch!
heroku buildpacks:set <your-github-url>#your-branch
```

## Tests

The buildpack tests use [Docker](https://www.docker.com/) to simulate
Heroku's stacks.

To run the test suite:

```
make test
```

Or to just test a specific stack:

```
make heroku-22-build
make heroku-24-build
make heroku-26-build
```

The tests are run via the vendored
[shunit2](https://github.com/kward/shunit2)
test framework.

To run just the unit tests (in Docker):

```
make unit
```

To lint and check formatting of the shell scripts:

```
make lint
```

### Debugging

To display the logged build outputs to assist with debugging, use the "echo" and "cat" commands. For example:

```sh
test() {
  local log_file var

  var="testtest"
  log_file=$(mktemp)
  echo "this is the log file" > "$log_file"
  echo "test log file" >> "$log_file"

  # use `echo` and `cat` for printing variables and reading files respectively
  echo $var
  cat $log_file

  # some cases when debugging is necessary
  assertEquals "$var" "testtest"
  assertFileContains "test log file" "$log_file"
}
```

Running the test above would produce:

```log
testtest
this is the log file
test log file
```

The test output writes to `$STD_OUT`, so you can use `cat $STD_OUT` to read output.
