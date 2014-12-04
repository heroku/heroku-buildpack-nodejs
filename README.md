Heroku Buildpack for io.js
============================

How it Works
------------

Here's an overview of what this buildpack does:

- Uses the [semver.io](https://semver.io) webservice to find the latest version of node that satisfies the [engines.node semver range](https://npmjs.org/doc/json.html#engines) in your package.json.
- Allows any recent version of node to be used, including [pre-release versions](https://semver.io/node.json).
- Uses the version of `npm` that comes bundled with `io`.
- Puts `node` and `npm` on the `PATH` so they can be executed with [heroku run](https://devcenter.heroku.com/articles/one-off-dynos#an-example-one-off-dyno).
- Runs `npm rebuild` if `node_modules` is checked into version control.
- Always runs `npm install` to ensure [npm script hooks](https://npmjs.org/doc/misc/npm-scripts.html) are executed.
- Always runs `npm prune` after restoring cached modules to ensure cleanup of unused dependencies.


Documentation
-------------

For more information about using io.js and buildpacks on Heroku, see these Dev Center articles:

- [Heroku Node.js Support](https://devcenter.heroku.com/articles/nodejs-support)
- [Getting Started with Node.js on Heroku](https://devcenter.heroku.com/articles/nodejs)
- [10 Habits of a Happy Node Hacker](https://blog.heroku.com/archives/2014/3/11/node-habits)
- [Buildpacks](https://devcenter.heroku.com/articles/buildpacks)
- [Buildpack API](https://devcenter.heroku.com/articles/buildpack-api)


Hacking
-------

To make changes to this buildpack, fork it on Github. Push up changes to your fork, then create a new Heroku app to test it, or configure an existing app to use your buildpack:

```
# Create a new Heroku app that uses your buildpack
heroku create --buildpack <your-github-url>

# Configure an existing Heroku app to use your buildpack
heroku config:set BUILDPACK_URL=<your-github-url>

# You can also use a git branch!
heroku config:set BUILDPACK_URL=<your-github-url>#your-branch
```


Testing
-------

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
