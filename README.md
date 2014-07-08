Buildpack for Node.js
=====================

This is a [buildpack](https://www.cloudcontrol.com/dev-center/Platform%20Documentation#buildpacks-and-the-procfile) for
Node.js apps, powered by [npm](https://npmjs.org/).

Usage
-----

This is our default buildpack for Node.js applications. In case you want to introduce some changes, fork our buildpack,
apply changes and test it via [custom buildpack feature](https://www.cloudcontrol.com/dev-center/Guides/Third-Party%20Buildpacks/Third-Party%20Buildpacks):

~~~bash
$ cctrlapp APP_NAME create custom --buildpack https://github.com/cloudControl/buildpack-nodejs.git
~~~

The buildpack will use npm to install your dependencies, vendoring a copy of the Node.js runtime into your web container.

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

- [node.js verions](http://cloudcontrolled.com.packages.s3.amazonaws.com/buildpack-nodejs/manifest.nodejs)
- [npm.js verions](http://cloudcontrolled.com.packages.s3.amazonaws.com/buildpack-nodejs/manifest.npm)


This is a [buildpack](https://www.cloudcontrol.com/dev-center/Platform%20Documentation#buildpacks-and-the-procfile) for
Node.js apps, powered by [npm](https://npmjs.org/).