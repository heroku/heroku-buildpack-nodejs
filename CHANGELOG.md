# Node.js Buildpack Changelog

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
