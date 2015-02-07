Buildpack for Node.js, io.js And Meteor
=======================================

This buildpack has been developped to deploy any node.js application
or an application based on the Meteor Framework (0.8+).

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

### Common

- Allows any recent version of node to be used, including [pre-release versions](https://semver.io/node.json).
- Discourages use of dangerous semver ranges like `*` and `>0.10`.
- Uses the version of `npm` that comes bundled with `node`.
- Puts `node` and `npm` on the `PATH` so they can be executed with [scalingo run](http://doc.scalingo.com/app/jobs).

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

- [Scalingo Node.js Support](http://doc.scalingo.com/languages/nodejs)
- [Buildpacks](http://doc.scalingo.com/buildpacks)
- [Getting Started with Node.js on Scalingo](http://doc.scalingo.com/languages/nodejs/getting-started-with-express)

## Options for Meteor

If you're using the meteor framework, you just need to commit the `.meteor` directory at the root of your
Meteor project, we'll detect and handle it to make your application work, out of the box.

### Specify a node version

You can define the node version you want to use with Meteor in the `.node-version` file at the root of your project.

```
0.11.x
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
