# Heroku Buildpack for Node.js

![nodejs](https://raw.githubusercontent.com/heroku/buildpacks/refs/heads/main/assets/images/buildpack-banner-node-js.png)

[![CI](https://github.com/heroku/heroku-buildpack-nodejs/actions/workflows/ci.yml/badge.svg)](https://github.com/heroku/heroku-buildpack-nodejs/actions/workflows/ci.yml)

This is the official [Heroku buildpack](https://devcenter.heroku.com/articles/buildpacks) for Node.js apps.

## Getting Started

See the [Getting Started with Node.js on Heroku](https://devcenter.heroku.com/articles/getting-started-with-nodejs) tutorial.

## Application Requirements

A `package.json` file must be present in the root (top-level) directory of your app's source code.

The buildpack supports the npm, Yarn, and pnpm package managers, selected by the lockfile present in your app:
- `package-lock.json` (npm)
- `yarn.lock` (Yarn)
- `pnpm-lock.yaml` (pnpm)

If no lockfile is found, npm is used. A lockfile is strongly recommended for reproducible builds.

## Configuration

### Node.js Version

Specify the Node.js version for your app with the `engines.node` field in `package.json`:

```json
{
  "engines": {
    "node": "24.x"
  }
}
```

We recommend using a major version range (like `24.x`) rather than pinning an exact version, so your app automatically receives Node.js security and bug-fix updates.

If you don't specify a version, the buildpack uses the current recommended LTS release.

For the list of supported Node.js versions, see [Heroku Node.js Support](https://devcenter.heroku.com/articles/nodejs-support).

## Documentation

For more information about using Node.js on Heroku, see [Dev Center](https://devcenter.heroku.com/categories/nodejs-support).
