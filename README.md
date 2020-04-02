# Heroku Buildpack for Node.js

![nodejs](https://cloud.githubusercontent.com/assets/51578/13712672/efdf2a40-e792-11e5-82ef-492478cbc0dc.png)

This is the official [Heroku buildpack](http://devcenter.heroku.com/articles/buildpacks) for Node.js apps.

[![Build Status](https://travis-ci.org/heroku/heroku-buildpack-nodejs.svg?branch=master)](https://travis-ci.org/heroku/heroku-buildpack-nodejs)

## Documentation

For more information about using this Node.js buildpack on Heroku, see these Dev Center articles:

- [Heroku Node.js Support](https://devcenter.heroku.com/articles/nodejs-support)
- [Getting Started with Node.js on Heroku](https://devcenter.heroku.com/articles/nodejs)

For more general information about buildpacks on Heroku:

- [Buildpacks](https://devcenter.heroku.com/articles/buildpacks)
- [Buildpack API](https://devcenter.heroku.com/articles/buildpack-api)

## Locking to a buildpack version

In production, you may want to lock dependencies - including
buildpacks - to a specific version.

First, find the version you want from
[the list of buildpack versions](https://github.com/heroku/heroku-buildpack-nodejs/releases).
Then, specify that version with `buildpacks:set`:

```
heroku buildpacks:set https://github.com/heroku/heroku-buildpack-nodejs#v170 -a my-app
```

If you have trouble upgrading to the latest version of the buildpack, please
open a support ticket at [help.heroku.com](https://help.heroku.com/) so we can assist.

### Chain Node with multiple buildpacks

This buildpack automatically exports node, npm, and any node_modules binaries
into the `$PATH` for easy use in subsequent buildpacks.

## Feedback

Having trouble? Dig it? Feature request?

- [help.heroku.com](https://help.heroku.com/)
- [@adamzdanielle](http://twitter.com/adamzdanielle)
- [GitHub issues](https://github.com/heroku/heroku-buildpack-nodejs/issues)

## Development

### Prerequisites

For local development, you may need the following tools:

- [Docker](https://hub.docker.com/search?type=edition&offering=community)
- [Go 1.14](https://golang.org/doc/install#install)
- [upx](https://upx.github.io/)

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
Heroku's Heroku-16 and Heroku-18 containers.

To run the test suite:

```
make test
```

Or to just test a specific stack:

```
make test-heroku-16
make test-heroku-18
```

The tests are run via the vendored
[shunit2](https://github.com/kward/shunit2)
test framework.

## Common Issues

### Proxy Issues

If your builds are not completing and have errors you may need to examine your build environment for `HTTP_PROXY`, `HTTPS_PROXY`, and `NO_PROXY` environment variables. A few examples of build output that may indicate issues with these values are below.

```
// ...
-----> Installing binaries
       engines.node (package.json):  10
       engines.npm (package.json):   unspecified (use default)

       Resolving node version 10...
       Error: Unknown error installing "10" of node

-----> Build failed
// ...
```

```
// ...
-----> Node.js app detected
curl: (35) OpenSSL SSL_connect: SSL_ERROR_SYSCALL in connection to lang-common.s3.amazonaws.com:443
// ...
```

If the environment where you are running the buildpack does not require a proxy to be used for HTTP connections you should try setting
the `NO_PROXY` environment variable to `amazonaws.com`, i.e. running the command `export NO_PROXY=amazonaws.com` immediatly before executing
the buildpack or by setting that environment value inside the buildpack. If you find `HTTP_PROXY` and `HTTPS_PROXY` environment variables and do not need a proxy in your build environment then the environment
variables should be removed.
