Heroku buildpack: Node.js with grunt support
============================================

Supported Grunt versions: 0.3 and 0.4.
See the Grunt [migration guide](https://github.com/gruntjs/grunt/wiki/Upgrading-from-0.3-to-0.4) if you are upgrading from 0.3.

This is a fork of [Heroku's official Node.js buildpack](https://github.com/heroku/heroku-buildpack-nodejs) with added [Grunt](http://gruntjs.com/) support.
Using this buildpack you do not need to commit the results of your Grunt tasks (e.g. minification and concatination of files), keeping your repository clean.

After all the default Node.js and NPM build tasks have finished, the buildpack checks if a Gruntfile (`Gruntfile.js`, `Gruntfile.coffee`or `grunt.js`) exists and executes the `heroku` task by running `grunt heroku`. For details about grunt and how to define tasks, check out the [offical documentation](http://gruntjs.com/getting-started). You must add grunt to the NPM dependencies in your `package.json` file.
If no Gruntfile exists, the buildpacks simply skips the grunt step and executes like the standard Node.js buildpack.

Usage
-----

Create a new app with this buildpack:

    heroku create myapp --buildpack https://github.com/mbuchetics/heroku-buildpack-nodejs-grunt.git

Or add this buildpack to your current app:

    heroku config:add BUILDPACK_URL=https://github.com/mbuchetics/heroku-buildpack-nodejs-grunt.git

Create your Node.js app and add a Gruntfile named  `Gruntfile.js` (or `Gruntfile.coffee` if you want to use CoffeeScript, or `grunt.js` if you are using Grunt 0.3) with a `heroku` task:

    grunt.registerTask('heroku', 'clean less mincss');

Don't forget to add grunt to your dependencies in `package.json`. If your grunt tasks depend on other pre-defined tasks make sure to add these dependencies as well:

    "dependencies": {
        ...
        "grunt": "*",
        "grunt-contrib": "*",
        "less": "*"
    }

Push to heroku

    git push heroku master
    ...
    -----> Heroku receiving push
    -----> Fetching custom buildpack... done
    -----> Node.js app detected
    -----> Resolving engine versions
           Using Node.js version: 0.8.2
           Using npm version: 1.1.41
    -----> Fetching Node.js binaries
    -----> Vendoring node into slug
    -----> Installing dependencies with npm
           ...
           Dependencies installed
    -----> Building runtime environment
    -----> Found gruntfile, running grunt heroku task
    Running "heroku" task
    ...
    -----> Discovering process types

Further Information
-------------------

[Heroku: Buildpacks](https://devcenter.heroku.com/articles/buildpacks)

[Heroku: Getting Started with Node.js](https://devcenter.heroku.com/articles/nodejs)

[Buildpacks: Heroku for Everything](http://blog.heroku.com/archives/2012/7/17/buildpacks/)

[Grunt: a task-based command line build tool for JavaScript projects](http://gruntjs.com/)