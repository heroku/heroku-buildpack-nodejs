Heroku Buildpack for Node.js
============================

This is a [Heroku buildpack](http://devcenter.heroku.com/articles/buildpacks) for Node.js apps.

The buildpack will detect your app as Node.js if it has a `package.json` file in the root.  It will use npm to install your dependencies, and vendors a version of the Node.js runtime into your slug.

Example Usage
-------------

    $ ls
    Procfile  package.json  web.js

    $ heroku create

    $ git push heroku master
    ...
    -----> Heroku receiving push
    -----> Fetching custom buildpack
    -----> Node.js app detected
    -----> Vendoring node 0.4.7
    -----> Installing dependencies with npm 1.0.8
           express@2.1.0 ./node_modules/express
           ├── mime@1.2.2
           ├── qs@0.3.1
           └── connect@1.6.2
           Dependencies installed

Node.js and npm versions
------------------------

You can specify the versions of Node.js and npm your application requires using `package.json`

```json
{
  "name": "myapp",
  "version": "0.0.1",
  "engines": {
    "node": "~0.10.13",
    "npm": "~1.3.2"
  }
}
```

To list the available versions of Node.js and npm, see these manifests:

- [heroku-buildpack-nodejs.s3.amazonaws.com/manifest.nodejs](http://heroku-buildpack-nodejs.s3.amazonaws.com/manifest.nodejs)
- [heroku-buildpack-nodejs.s3.amazonaws.com/manifest.npm](http://heroku-buildpack-nodejs.s3.amazonaws.com/manifest.npm)

Documentation
-------------

For more information about buildpacks and Node.js, see these Dev Center articles:

- [Getting Started with Node.js on Heroku](https://devcenter.heroku.com/articles/nodejs)
- [Heroku Node.js Support](https://devcenter.heroku.com/articles/nodejs-support)
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