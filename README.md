Buildpack for Node.js, io.js And Meteor
=======================================

![nodejs](https://cloud.githubusercontent.com/assets/51578/13712672/efdf2a40-e792-11e5-82ef-492478cbc0dc.png)

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

**Adding `node_modules` directory in git repository is an antipattern.**

### Specify Node.js/NPM version

Node.js and NPM version are read from the `engines` section of the `package.json` file: https://doc.scalingo.com/languages/nodejs/start#specifying-a-nodejs-version

### Common

- Allows any recent version of node to be used, including [pre-release versions](https://semver.scalingo.com/node.json).
- Discourages use of dangerous semver ranges like `*` and `>0.10`.
- Uses the version of `npm` that comes bundled with `node`.
- Puts `node` and `npm` on the `PATH` so they can be executed with [scalingo run](https://doc.scalingo.com/app/tasks).

### Caching

- Caches the `node_modules` directory across builds for fast deploys.
- Meteor specific: we cache the meteor bundle to avoid spending time downloading it at each deployment
- Doesn't use the cache if `node_modules` is checked into version control.
- Runs `npm rebuild` if `node_modules` is checked into version control.
- Always runs `npm install` to ensure [npm script hooks](https://docs.npmjs.com/cli/v8/using-npm/scripts) are executed.
- Always runs `npm prune` after restoring cached modules to ensure cleanup of unused dependencies.

For more technical details, see the [compile script](https://github.com/Scalingo/nodejs-buildpack/blob/master/bin/compile).

## Documentation

For more information about using Node.js and buildpacks on Scalingo, see these Documentation pages:

- [Scalingo Node.js Support](https://doc.scalingo.com/languages/nodejs/start)
- [Scalingo Meteor Support](https://doc.scalingo.com/languages/meteorjs/start)
- [Buildpacks](https://doc.scalingo.com/buildpacks)
- [Getting Started with Node.js on Scalingo](https://doc.scalingo.com/languages/nodejs/tutorial)
- [Getting Started with Meteor on Scalingo](https://doc.scalingo.com/languages/meteorjs/tutorial)

## Debug build

### Meteor

By default, Meteor minify all your assets to stand in one single javascript file,
if you want to make a 'debug' build (assets unminified), please defined the following
environment variable:

```shell
scalingo -a app-name env-set METEOR_DEBUG_BUILD=true
```

## Options for Meteor

If you're using the meteor framework, you just need to commit the `.meteor`
directory at the root of your Meteor project, we'll detect and handle it to
make your application work, out of the box.

If you are using Meteor ≥ 1.3, the flag `--server-only` will be used automatically
to build your application for Meteor mobile integration.

### Memory in the build process

Meteor build is handled by a Node.JS process which has a default limit:
it can't use more than ~3.7GB of RAM. It can be too little for large Meteor
applications and the build process will fail with the following error:
`Allocation failed`.

The buildpack is fixing this issue by adding to the environment variable
`TOOL_NODE_FLAGS`, the flag `--max-old-space-size=8192` (except if this
precise flag is already defined).

To update the value `8192`, the variable `BUILD_MAX_MEMORY` can be overriden.

### Starting flags for `node` process

For some reasons, you may want to use custom flags to run your application.
The following environment variable let you customize this.

Example: (when meteor need to use 4GB of RAM)

```shell
scalingo -a app-name env-set NODE_BOOT_FLAGS="--max-old-space-size=4096"
```

## Options for Node

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
scalingo -a app-name env-set NPM_CONFIG_PRODUCTION=true
```

To install *dependencies and devDependencies:*

```shell
scalingo -a app-name env-set NPM_CONFIG_PRODUCTION=false
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

```shell
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

## Feedback or want to report an issue

- [GitHub issues](https://github.com/Scalingo/nodejs-buildpack/issues)

## Hacking

To make changes to this buildpack, fork it on Github. Push up changes to your fork, then create a new Scalingo app to test it, or configure an existing app to use your buildpack:

```shell
# Configure an existing Scalingo app to use your buildpack
scalingo -a app-name env-set BUILDPACK_URL=<your-github-url>

# You can also use a git branch!
scalingo -a app-name env-set BUILDPACK_URL=<your-github-url>#your-branch
```

## Tests

The buildpack tests use [Docker](https://www.docker.com/) to simulate
Scalingo environment.

To run the test suite:

```shell
make test
```

The tests are run via the vendored
[shunit2](https://github.com/kward/shunit2)
test framework.

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
