Heroku Buildpack for Node.js
============================

This is a [Heroku buildpack](http://devcenter.heroku.com/articles/buildpacks) for Node.js apps. It will detect your app as Node.js if it has a `package.json` file in the root. It uses npm to install your dependencies, and vendors a version of the Node.js runtime into your slug.

If you specify a version of node in the [`engines` field of your package.json](https://npmjs.org/doc/json.html#engines), the buildpack will attempt to find the specified version on [nodejs.org/dist](http://nodejs.org/dist/) and download it from our S3 caching proxy.

If you don't specify a version of node, the latest stable version will be used.

About this Refactor
-------------------

This branch of the buildpack is intended to replace the [official Node.js buildpack](https://github.com/heroku/heroku-buildpack-nodejs#readme) once it has been tested by some users. To use this buildpack for your node app, simply change your BUILDPACK_URL [config var](https://devcenter.heroku.com/articles/config-vars) and push your app to heroku.

```
heroku config:set BUILDPACK_URL=https://github.com/heroku/heroku-buildpack-nodejs#diet -a my-node-app
git commit -am "fakeout" --allow-empty
git push heroku
```

Here's a summary of the differences between the current official buildpack and this _diet_ version:

The old buildpack:

- Contains a lot of code for compiling node and npm binaries and moving them to S3. This code is orthogonal to the core function of the buildpack, and is only used internally by Node maintainers at Heroku.
- Downloads and compiles node and npm separately.
- Requires manual intervention each time a new version of node or npm is released.
- Does not support pre-release versions of node.
- Uses SCONS to support really old versions of node and npm.
- Maintains S3 manifests of our hand-compiled versions of node and npm.
- Does not cache anything.

The new buildpack:

- Uses the latest stable version of node and npm by default.
- Allows any recent version of node to be used, including pre-release versions, as soon as they become available on [nodejs.org/dist](http://nodejs.org/dist/).
- Uses the version of npm that comes bundled with node instead of downloading and compiling them separately. npm has been bundled with node since [v0.6.3 (Nov 2011)](http://blog.nodejs.org/2011/11/25/node-v0-6-3/). This effectively means that node versions `<0.6.3` are no longer supported, and that the `engines.npm` field in package.json is now ignored.
- Makes use of an s3 caching proxy of nodejs.org for faster downloads of the node binaries.
- Makes fewer HTTP requests when resolving node versions.
- Uses an updated version of [node-semver](https://github.com/isaacs/node-semver) for dependency resolution.
- No longer depends on SCONS.
- Caches the `node_modules` directory across builds.
- Runs `npm prune` after restoring cached modules, to ensure that any modules formerly used by your app aren't needlessly installed and/or compiled.

Documentation
-------------

For more information about buildpacks and Node.js, see these Dev Center articles:

- [Heroku Node.js Support](https://devcenter.heroku.com/articles/nodejs-support)
- [Getting Started with Node.js on Heroku](https://devcenter.heroku.com/articles/nodejs)
- [Buildpacks](https://devcenter.heroku.com/articles/buildpacks)
- [Buildpack API](https://devcenter.heroku.com/articles/buildpack-api)

Hacking
-------

To make changes to this buildpack, fork it on Github. Push up changes to your fork, then create a new Heroku app to test it, or configure an existing app to use your buildpack:

```sh
# Create a new Heroku app that uses your buildpack
heroku create --buildpack <your-github-url>

# Configure an existing Heroku app to use your buildpack
heroku config:set BUILDPACK_URL=<your-github-url>

# You can also use a git branch!
heroku config:set BUILDPACK_URL=<your-github-url>#your-branch
```

For more detailed information about testing buildpacks, see [CONTRIBUTING.md](CONTRIBUTING.md)
