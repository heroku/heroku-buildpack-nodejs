# Node.js Buildpack Changelog

## master
- Update Travis badge to `master` and other changes in README ([#753](https://github.com/heroku/heroku-buildpack-nodejs/pull/753))

## v170 (2020-03-31)
- Bump rake from 12.3.1 to 12.3.3 ([#742](https://github.com/heroku/heroku-buildpack-nodejs/pull/742))
- Upgrade Go to 1.14 ([#744](https://github.com/heroku/heroku-buildpack-nodejs/pull/744))
- Bump `npm ci` usage for installing dependencies to 20% ([#745](https://github.com/heroku/heroku-buildpack-nodejs/pull/745))
- Detect Yarn 2 usage, produce error message, and fail build (until supported) ([#746](https://github.com/heroku/heroku-buildpack-nodejs/pull/746))
- Compress yq binaries ([#748](https://github.com/heroku/heroku-buildpack-nodejs/pull/748))
- Move etc/vendor to lib/vendor ([#750](https://github.com/heroku/heroku-buildpack-nodejs/pull/750))

## v167 (2020-02-06)
- Make minor upgrades to gems ([#735](https://github.com/heroku/heroku-buildpack-nodejs/pull/735))
- Fix typo in failure metadata call ([#737](https://github.com/heroku/heroku-buildpack-nodejs/pull/737))

## v166 (2019-12-16)
- Add Node 13 metrics plugin ([#731](https://github.com/heroku/heroku-buildpack-nodejs/pull/731), [#732](https://github.com/heroku/heroku-buildpack-nodejs/pull/732))
- Fix yarn cache feature flag ([#729](https://github.com/heroku/heroku-buildpack-nodejs/pull/729))

## v165 (2019-10-24)
- Update README ([#725](https://github.com/heroku/heroku-buildpack-nodejs/pull/725))
- Update default Node version to 12.x ([#724](https://github.com/heroku/heroku-buildpack-nodejs/pull/724))

## v164 (2019-10-17)
- Avoid issues in environments requiring proxies for all connections (#708)
- Extend metadata module in preparation for bin/report work (#709)
- Vendor the buildpack stdlib (#710)
- Check the status code when listing S3 buckets (#711)
- Rename script monitoring metadata (#719)
- Extend bin/report (#718)

## v163 (2019-09-12)
- Add a minimal version of bin/report. Not user-facing (#700)

## v162 (2019-09-03)
- Replace broken kb.heroku.com links with help.heroku.com shortlinks (#698)

## v161 (2019-08-15)
- Expand A/B test of native yarn caching to 50% of apps (#695)

## v160 (2019-08-07)
- Roll out A/B test of native yarn caching to a small set of apps (#693)

## v159 (2019-08-01)
- Updates to metadata saved (#689, #690)
- Add native yarn cache caching behind a flag (#691)

## v158 (2019-07-10)
- Don't suppress curl errors (#680)
- Add logging to track yarn workspace usage (#685)
- Log out number of js, jsx, and ts files (#686)

## v157 (2019-06-17)
- Prevent `HTTP_PROXY` env var from blocking version-resolution binary

## v156 (2019-06-12)
- Turn off npm ci experiment

## v155 (2019-06-06)
- Add metadata for build steps (#677)

## v154 (2019-06-05)
- Roll out A/B test of npm ci command to 5% of apps (#676)
- Internal fixes (#674, #673)

## v153 (2019-05-30)
- Test new A/B testing module (#671, #672)

## v152 (2019-05-28)
- Replace nodebin usage in hatchet tests (#669)
- Add ability to list all node or yarn releases (#668)

## v151 (2019-05-28)
- Deprecate nodebin in favor of go binary (#667)

## v150 (2019-05-22)
- Resolve more inconsistencies with version selection (#666)

## v149 (2019-05-10)
- Resolve the known behavior mismatches between nodebin and the go logic (#664)

## v148 (2019-05-02)
- Dark-launch new semver matching logic for node binaries (#663)

## v147 (2019-05-01)
- Dark-launch new semver matching logic for yarn binaries (#661)
- Add node 12.x as a supported version for Node Metrics beta (#662)

## v146 (2019-04-25)
- Deprecate io.js as an alternative runtime (#658)
- Prototyping new version resolution approach to replace Nodebin (#649 - #657)

## v145 (2019-04-16)
- Separate prebuild step in log output (#646)
- Clean up script metrics and logging (#647)

## v144 (2019-04-08)
- Remove temporary wraning about "run build" change (#644)

## v143 (2019-03-28)
- Internal logging changes (#637, #631, #630)

## v142 (2019-03-11)
- Add temporary warning about "run build" when the build fails as well (#639)

## v141 (2019-03-11)
- Add temporary warning about "run build" change to log output (#636)

## v140 (2019-03-11)
- Run the build script by default (#628)

## v139 (2019-03-04)
- Make breaking change warning header brighter (#627)

## v138 (2019-02-20)
- Add new Build header (#625)
- Fix yarn run error when script is empty string (#624)

## v137 (2019-02-14)
- Internal logging changes (#620, #618, #621)
- Detect build scripts even when they are empty (#617)

## v136 (2019-02-09)
- Add warning for the upcoming run build change (#616)

## v135 (2019-02-06)

- Fix bug where failing builds on CI would not fail CI (#613)
- Internal logging changes (#596, #600)

## v134 (2018-12-20)

- Internal changes (#593, #591)
- Handle `$MEMORY_AVAILABLE` when `memory.limit_in_bytes` is nonsensically large (#531)

## v133 (2018-11-28)

- Add warning for flatmap-stream 404 failure (#590)

## v132 (2018-11-12)

- Quietly add new build script behavior behind a flag (#584, #585)
- Move cache directory layout (#587)

## v131 (2018-10-31)

- Improve bin/detect error messages (#575)
- Add support for Node 11 (#578, #582, #580)
- Update default Node version to 10.x

## v130 (2018-10-03)

- Unpin Yarn from 1.9.x (#569)

## v129 (2018-10-02)

- Fix a bug with formatting (#572)
- internal changes (#567)

## v128 (2018-09-13)

- Default to Yarn 1.9.x to avoid a bug (#568)

## v127 (2018-09-13)

- interal changes (#566)

## v126 (2018-09-06)

- Icrease Node memory default during builds (#561)
- Rework output when caching directories (#559)
- Only write export script if directory is writeable (#539)
- Testing changes (#552, #557, #558)
- Upgrade the Node Metrics plugin (#564)

## v125 (2018-08-24)

- Fix issue with old Node and metrics plugin (#555)

## v124 (2018-08-23)

- Add plugin for [Node.js Language Metrics](https://devcenter.heroku.com/articles/language-runtime-metrics-nodejs)

## v123 (2018-03-14)

- Internal logging changes

## v122 (2018-03-13)

- Internal logging changes

## v121 (2018-03-02)

- Skip pruning if `NPM_CONFIG_PRODUCTION` or `YARN_PRODUCTION` is defined (#529)

## v120 (2018-03-01)

- Skip pruning for versions of npm with known issues with git submodules (#528)
- Add timing metrics (#527)

## v119 (2018-02-28)

- Install and prune devDependencies by default (#519)
- [Breaking] Stop setting the env var `NPM_CONFIG_PRODUCTION=true` by default

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
