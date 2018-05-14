# Node.js Buildpack Changelog

## Master

## v121 (2018-03-02)

- Skip pruning if `NPM_CONFIG_PRODUCTION` or `YARN_PRODUCTION` is defined (#529)

## v120 (2018-03-01)

- Skip pruning for versions of npm with known issues with git submodules (#528)
- Add timing metrics (#527)

## v119 (2018-02-28)

- Install and prune devDependencies by default (#519)

## v118 (2018-02-02)

- Fix issue with `NODE_ENV` in CI (#513)

## v117 (2018-01-31)

- Fix bug with previous default cache directories fix for npm and yarn (#511)

## v116 (2018-01-29)

- Fix metrics typo (#510)

## v115 (2017-01-25)

- Add metrics to track new types of failure (#509)

## v114 (2017-11-16)

- Don't default to npm 5.x if the user already has npm >= 5 (#499)

## v113 (2017-11-13)

- Bump default version of Node to Node 8 (#497)

## v112 (2017-11-13)

- Move default Yarn and npm cache directories to a temporary dir (#459)
- `LOG_CONCURRENCY` fix (#475)
- Default Yarn to `1.x`
- Add `BUILD_DIR` to env var blacklist

## v111 (2017-09-06)

- Move `WEB_CONCURRENCY` logic to separate file (#467)
- Temporarily default Yarn to known-good version

## v110 (2017-07-26)

- Improve error messages when bin version requirements are invalid (#457)

## v109 (2017-07-25)

- Switch to using nodebin to download the node binary (#451)

## v108 (2017-07-24)

- Add `$STACK` to the cache signature (#445)
- Log output now differentiates between an empty cache and a new cache signature (#448)
- Remove the use of semver.io to bootstrap npm (#452)
- Switch to using nodebin to download iojs binaries (#450)

## v107 (2017-07-17)

- Switch to using nodebin to download the yarn binary (#444)

## v106 (2017-06-19)

- Default to npm v5 if `package-lock.json` is present (#429)

## v105 (2017-05-26)

- Break the build if yarn and npm lockfiles are both included (#411)

## v104 (2017-05-22)

- Add `$PREBUILD` to cache signature (#405)
- Check for `.heroku/node` existence (#384)
- Add `NODE_ENV=test` to `test-compile` (#403)
- Install `yarn` if a version is defined in `engines` (#404)

## v101 (2017-04-26)

- Instrument metrics logging
- Undo the Prepend a leading 0 to `WEB_CONCURRENCY` change

## v99 (2017-04-17)

- Use yarn in CI tests if available
- Prepend a leading 0 to `WEB_CONCURRENCY`

## v98 (2017-01-31)

- Default to the latest LTS node version (6.x)

## v97 (2017-01-31)

- Cache node_modules
- No longer run `yarn check`

## v96 (2017-01-27)

- Clear caches from the slug
- Warn, rather than failing, on a failed `yarn check`

## v95 (2017-01-27)

- Use cache directories instead of node_modules
- Use yarn, if available, as part of the cache signature
- Warn about yarn's youth and evolution on build failures
- Link to opt-out of yarn instructions
- Use `yarn list` instead of `yarn ls`
- Hide final dep tree listings under a `NODE_VERBOSE` flag

## v94 (2016-12-16)

- Warn on yarn NODE_ENV and NPM_CONFIG incompatibility
- Pass --ignore-engines flag to yarn to avoid hard failures

## v93 (2016-12-16)

- Use yarn instead of npm if yarn.lock file is present

## v91 (2016-7-7)

- Do not fail build on output errors
- Do not prune before install (shrinkwrap unsupported by prune)
- Extended warnings (missing dependencies, econnreset, no start)
- Remove hard limit on WEB_CONCURRENCY (32)

## v90 (2016-4-20)

- Blacklists the LANG env var

## v89 (2016-3-11)

- Adds heroku-prebuild script
- Adds heroku-postbuild script

## v88 (2016-2-23)

- Retries all curl requests
- Use HTTPS for node binary downloads again

## v87 (2015-11-03)

Several edge-case fixes

- Enables compiling the same directory multiple times
- Updates tests for Node v5
- Moves node_modules/.bin binaries to last on the PATH

## v86 (2015-10-08)

Fixes piped output buffering issues

## v85 (2015-10-08)

Fixes piped output buffering issues (unsuccessful)

- https://github.com/heroku/heroku-buildpack-nodejs/issues/273

## v84 (2015-10-08)

Replaces sed with awk for output formatting

- large output (from assets or npm 3) was crashing sed ('resource unavailable')

## v83 (2015-10-05)

Caching improvements

- Fixes modules-checked-in reference URL
- When cache restoration is disabled, empties the cache instead of saving it
- Adds bower_components as a default cache target

## v82 (2015-09-30)

Detects bower+angular resolution failures
Detects missing grunt/gulp/bower failures

## v81 (2015-09-24)

Supports WEB_CONCURRENCY=28 for Performance-L dynos

## v80 (2015-08-14)

Fixes not defaulting to `NODE_ENV=production` during runtime

## v79 (2015-08-10)

Supports WEB_CONCURRENCY for Performance-M dynos

## v78 (2015-07-24)

Defaults node environment to 'production'; bugfixes

- Fix runtime signature cache invalidation
- Provide error messaging for un-downloadable binaries
- Default to NODE_ENV=production for both build and runtime
- https://github.com/heroku/heroku-buildpack-nodejs/issues/60

## v77 (2015-07-15)

Npm bootstrapping skipped when using iojs.

- Fixes https://github.com/heroku/heroku-buildpack-nodejs/issues/202

## v76 (2015-06-23)

Refactor to bring caching logic to the forefront.

- Fixes cachDirectories issues
- Addresses https://github.com/heroku/heroku-buildpack-nodejs/pull/231
- Addresses https://github.com/heroku/heroku-buildpack-nodejs/issues/226
- Simplifies detect (package.json required)

## v75 (2015-04-24)

Updated build failure and help messaging.

## v74 (2015-04-24)

Updated messaging.

## v73 (2015-04-24)

Disables cache restoration if node_modules already exists.

## v72 (2015-04-23)

Accepts `cacheDirectories` array in package.json to override default `node_modules` caching.

- Documented at https://devcenter.heroku.com/articles/nodejs-support#cache-behavior
