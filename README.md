# Heroku Node.js Buildpack: Yoga

Preview the next version of the node buildpack: yoga.
It's the most powerful and flexible Node buildpack yet.

```shell
heroku config:set BUILDPACK_URL=https://github.com/heroku/heroku-buildpack-nodejs#yoga
git commit -am 'yoga' --allow-empty
git push heroku master
```

It's still in beta and we'd love [feedback](#feedback)!

## What can I do with Yoga?

- [Specify an npm version](https://github.com/heroku/heroku-buildpack-nodejs/tree/yoga#specify-an-npm-version)
- [Enable or disable node_modules caching](https://github.com/heroku/heroku-buildpack-nodejs/tree/yoga#enable-or-disable-node_modules-caching)
- [Enable or disable devDependencies installation](https://github.com/heroku/heroku-buildpack-nodejs/tree/yoga#enable-or-disable-devdependencies-installation)
- [Configure npm with .npmrc](https://github.com/heroku/heroku-buildpack-nodejs/tree/yoga#configure-npm-with-npmrc)
- [Chain node with multiple buildpacks](https://github.com/heroku/heroku-buildpack-nodejs/tree/yoga#chain-node-with-multiple-buildpacks)

Yoga also outputs minimal but useful messages on success and concise debug information on error.
No more 20,000-line error logs!

## Stretch

### Specify a node version

Set engines.node in package.json to the semver range
(or specific version) of node you'd like to use.
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

Sometimes it's necessary to be able to build without any cache present.

Caching node_modules between builds can dramatically speed up build times.
However, `npm install` doesn't automatically update already installed modules
as long as they fall within acceptable semver ranges,
which can lead to outdated modules.

```shell
heroku config:set DISABLE_BUILD_CACHE=true
git commit -am 'build' --allow-empty
git push heroku master
heroku config:unset DISABLE_BUILD_CACHE
```

Default: `DISABLE_BUILD_CACHE` defaults to false

### Enable or disable devDependencies installation

During local development, `npm install` installs all dependencies
and all devDependencies (test frameworks, build tools, etc).
This is usually something you want to avoid in production, so
npm has a 'production' config that can be set through the environment:

To install *dependencies only:*

```shell
heroku config:set NPM_CONFIG_PRODUCTION=true
```

To install *dependencies and devDependencies:*

```shell
heroku config:set NPM_CONFIG_PRODUCTION=false
```

Default: `NPM_CONFIG_PRODUCTION` defaults to true on Heroku

### Configure npm with .npmrc

Sometimes, a project needs custom npm behavior to set up proxies,
use a different registry, etc. For such behavior,
just include an `.npmrc` file in the root of your project:

```
# .npmrc
registry = 'https://custom-registry.com/'
```

### Chain Node with multiple buildpacks

Frequently, Node is paired with other platforms like Ruby or PHP
through Heroku's Multi Buildpack. In order to use node in
another environment, specify this buildpack first in your .buildpacks file.
This buildpack automatically exports node, npm, and any node_modules binaries
into the `$PATH` for easy use in subsequent buildpacks.

## Roadmap

The next features in the pipeline include:

- Specifying io.js as your node engine
- Providing proxy settings for your locked-down enterprise environment

## Feedback

Having trouble? Dig it? Feature request?

- [help.heroku.com](https://help.heroku.com/)
- [@hunterloftis](http://twitter.com/hunterloftis)
- [github issues](https://github.com/heroku/heroku-buildpack-nodejs/issues)

## Testing

[Anvil](https://github.com/ddollar/anvil) is a generic build server for Heroku.

```
gem install anvil-cli
```

The [heroku-anvil CLI plugin](https://github.com/ddollar/heroku-anvil) is a wrapper for anvil.

```
heroku plugins:install https://github.com/ddollar/heroku-anvil
```

The [ddollar/test](https://github.com/ddollar/buildpack-test) buildpack runs `bin/test` on your app/buildpack.

```
heroku build -b ddollar/test # -b can also point to a local directory
```

For more info on testing, see [Best Practices for Testing Buildpacks](https://discussion.heroku.com/t/best-practices-for-testing-buildpacks/294) on the Heroku discussion forum.
