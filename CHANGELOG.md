# Node.js Buildpack Changelog

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
