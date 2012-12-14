Heroku buildpack: Node.js with grunt support
============================================

This is a fork of [Heroku's official Node.js buildpack](https://github.com/heroku/heroku-buildpack-nodejs) with added [grunt](https://github.com/cowboy/grunt) support.
Using this buildpack you do not need to commit the results of your grunt tasks (e.g. minification and concatination of files), keeping your repository clean. 

After all the default Node.js and NPM build tasks have finished, the buildpack checks if a gruntfile (`grunt.js`, `Gruntfile.js`, `Gruntfile.coffee`) exists and executes the `heroku` task by running `grunt heroku`. For details about grunt and how to define tasks, check out the [offical documentation](https://github.com/cowboy/grunt). You must add grunt to the NPM dependencies in your `package.json` file.
If no gruntfile exists, the buildpacks simply skips the grunt step and executes like the standard Node.js buildpack.

Usage
-----

Create a new app with this buildpack:

    heroku create myapp --buildpack https://github.com/mbuchetics/heroku-buildpack-nodejs-grunt.git

Or add this buildpack to your current app:

    heroku config:add BUILDPACK_URL=https://github.com/mbuchetics/heroku-buildpack-nodejs-grunt.git

Create your Node.js app and add a gruntfile named  `grunt.js` (also works with `Gruntfile.js` or `Gruntfile.coffee`) with a `heroku` task:

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

