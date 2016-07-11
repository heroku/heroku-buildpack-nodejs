Buildpack for Node.js, io.js And Meteor
=======================================

![nodesjs](https://cloud.githubusercontent.com/assets/51578/8882955/3f0c3980-3219-11e5-8666-bc9c926a7356.jpg)

This buildpack has been developped to deploy any node.js application
or an application based on the Meteor Framework (0.9+).

It is based on the original nodejs buildpack and has been updated to
get an out of the box experience for Meteor.

## How it Works

Apps are built via one of four paths:

1. A regular `npm install` (first build; default scenario)
2. Copy existing `node_modules` from cache, then `npm prune`, then `npm install` (subsequent builds)
3. Skip dependencies (if package.json doesn't exist but server.js does)
4. Skip cache, run `npm rebuild` before `npm install` (`node_modules` are checked into source control)

You should only use #3 (omitting package.json) for quick tests or experiments.
You should never use #4 - it's included for backwards-compatibility and will generate warnings.

**Checking in `node_modules` is an antipattern.**
For more information, see [the npm docs](https://docs.npmjs.com/misc/faq#should-i-check-my-node_modules-folder-into-git-)

### Install last Node.js version

#### NodeJS

Uses the [semver.io](https://semver.io) webservice to find the latest version of node that satisfies the [engines.node semver range](https://npmjs.org/doc/json.html#engines) in your package.json.

#### Meteor

You can write a file `.node_version` at the root of your project, and we'll use semver to get the best node version from this instruction

##### Debug Build

Define the environment variable `METEOR_DEBUG_BUILD` to true and we'll build your application in debug mode (unminifed code)

```
scalingo env-set METEOR_DEBUG_BUILD=true
```

### Common

- Allows any recent version of node to be used, including [pre-release versions](https://semver.io/node.json).
- Discourages use of dangerous semver ranges like `*` and `>0.10`.
- Uses the version of `npm` that comes bundled with `node`.
- Puts `node` and `npm` on the `PATH` so they can be executed with [scalingo run](http://doc.scalingo.com/app/tasks).

### Caching

- Caches the `node_modules` directory across builds for fast deploys.
- Meteor specific: we cache the meteor bundle to avoid spending time downloading it at each deployment
- Doesn't use the cache if `node_modules` is checked into version control.
- Runs `npm rebuild` if `node_modules` is checked into version control.
- Always runs `npm install` to ensure [npm script hooks](https://npmjs.org/doc/misc/npm-scripts.html) are executed.
- Always runs `npm prune` after restoring cached modules to ensure cleanup of unused dependencies.

For more technical details, see the [compile script](https://github.com/Scalingo/nodejs-buildpack/blob/master/bin/compile).

## Documentation

For more information about using Node.js and buildpacks on Scalingo, see these Dev Center articles:

- [Scalingo Node.js Support](http://doc.scalingo.com/languages/javascript/nodejs)
- [Buildpacks](http://doc.scalingo.com/buildpacks)
- [Getting Started with Node.js on Scalingo](http://doc.scalingo.com/languages/javascript/nodejs/getting-started-with-nodejs)
- [Getting Started with Meteor on Scalingo](http://doc.scalingo.com/languages/javascript/nodejs/getting-started-with-meteor)
- [Getting Started with io.js on Scalingo](http://doc.scalingo.com/languages/javascript/iojs/getting-started-with-iojs)

## Options for Meteor

If you're using the meteor framework, you just need to commit the `.meteor`
directory at the root of your Meteor project, we'll detect and handle it to
make your application work, out of the box.

### Build mobile server backend for cordova

You've to setup the `BUILD_MOBILE_PLATFORMS_SERVER` environment variable to true.

```
scalingo env-set BUILD_MOBILE_PLATFORMS_SERVER=true
```

Then the buildpack will user the `--server-only` flag of Meteor (≥ 1.3)

### Specify a node version

You can define the node version you want to use with Meteor in the `.node-version` file at the root of your project.

```
0.11.x
```

### Starting flags for `node` process

```
scalingo env-set NODE_BOOT_FLAGS="--max-old-space-size=4096"
```

## Options for Node

### Specify a node version

Set engines.node in package.json to the semver range (or specific version) of node you'd like to use.
(It's a good idea to make this the same version you use during development)

```json
"engines": {
  "node": "0.11.x"
}
```

```json
"engines": {
  "node": "0.10.33"
}
```

Default: the
[latest stable version.](http://semver.io/node)

### Specify an npm version

Set engines.npm in package.json to the semver range
(or specific version) of npm you'd like to use.
(It's a good idea to make this the same version you use during development)

Since 'npm 2' shipped several major bugfixes, you might try:

```json
"engines": {
  "npm": "2.x"
}
```

```json
"engines": {
  "npm": "^2.1.0"
}
```

Default: the version of npm bundled with your node install (varies).

### Enable or disable node_modules caching

For a 'clean' build without using any cached node modules:

```shell
scalingo env-set NODE_MODULES_CACHE=false
git commit -am 'rebuild' --allow-empty
git push scalingo master
scalingo env-unset NODE_MODULES_CACHE
```

Caching node_modules between builds dramatically speeds up build times.
However, `npm install` doesn't automatically update already-installed modules
as long as they fall within acceptable semver ranges,
which can lead to outdated modules.

Default: `NODE_MODULES_CACHE` defaults to true

### Enable or disable devDependencies installation

During local development, `npm install` installs all dependencies
and all devDependencies (test frameworks, build tools, etc).
This is usually something you want to avoid in production, so
npm has a 'production' config that can be set through the environment:

To install *dependencies only:*

```shell
scalingo env-set NPM_CONFIG_PRODUCTION=true
```

To install *dependencies and devDependencies:*

```shell
scalingo env-set NPM_CONFIG_PRODUCTION=false
```

Default: `NPM_CONFIG_PRODUCTION` defaults to true on Scalingo

### Configure npm with .npmrc

Sometimes, a project needs custom npm behavior to set up proxies,
use a different registry, etc. For such behavior,
just include an `.npmrc` file in the root of your project:

```
# .npmrc
registry = 'https://custom-registry.com/'
```

### Reasonable defaults for concurrency

This buildpack adds two environment variables: `WEB_MEMORY` and `WEB_CONCURRENCY`.
You can set either of them, but if unset the buildpack will fill them with reasonable defaults.

- `WEB_MEMORY`: expected memory use by each node process (in MB, default: 512)
- `WEB_CONCURRENCY`: recommended number of processes to Cluster based on the current environment

Clustering is not done automatically; concurrency should be part of the app,
usually via a library like [throng](https://github.com/hunterloftis/throng).
Apps without any clustering mechanism will remain unaffected by these variables.

This behavior allows your app to automatically take advantage of larger containers.
The default settings will cluster
1 process on a S and M containers, 2 processes on L containers and 4 on XL containers.

For example, when your app starts:

```
app[web-1]: Detected 1024 MB available memory, 512 MB limit per process (WEB_MEMORY)
app[web-1]: Recommending WEB_CONCURRENCY=2
app[web-1]:
app[web-1]: > example-concurrency@1.0.0 start /app
app[web-1]: > node server.js
app[web-1]: Listening on 51118
app[web-1]: Listening on 51118
```

### Chain Node with multiple buildpacks

This buildpack automatically exports node, npm, and any node_modules binaries
into the `$PATH` for easy use in subsequent buildpacks.

## Feedback

- [github issues](https://github.com/Scalingo/nodejs-buildpack/issues)

## Hacking

To make changes to this buildpack, fork it on Github. Push up changes to your fork, then create a new Scalingo app to test it, or configure an existing app to use your buildpack:

```
# Configure an existing Scalingo app to use your buildpack
scalingo env-set BUILDPACK_URL=<your-github-url>

# You can also use a git branch!
scalingo env-set BUILDPACK_URL=<your-github-url>#your-branch
```

## Testing

The buildpack tests use [Docker](https://www.docker.com/) to simulate
Scalingo environment.

To run the test suite:

```
make test
```

The tests are run via the vendored [shunit2](http://shunit2.googlecode.com/svn/trunk/source/2.1/doc/shunit2.html)
test framework.
