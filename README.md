Buildpack for Node.js And Meteor
=========================================

This buildpack has been developped to deploy any node.js application
or an application based on the Meteor Framework (0.8+).

It is based on the original nodejs buildpack and has been updated to
get an out of the box experience for Meteor.


How it Works
------------

Here's an overview of what this buildpack does:

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


Documentation
-------------

For more information about using Node.js and buildpacks on Scalingo, see these Dev Center articles:

- [Scalingo Node.js Support](http://doc.scalingo.com/languages/nodejs)
- [Buildpacks](http://doc.scalingo.com/buildpacks)
