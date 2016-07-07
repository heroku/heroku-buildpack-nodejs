# Node.js Buildpack Changelog

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
