# Yarn v2 Plugin: Prune devDependencies

Unlike Yarn v1 and NPM, Yarn v2 doesn't support pruning `devDependencies` as part of the
install step. This project adds a custom plugin to be included in builds using Yarn v2 to 
restore this functionality.
              
The default handling of dependencies for both NPM and Yarn is:
* install all dependencies
* run pre-build and post-build scripts
* remove development dependencies that have been installed

This allows an application to successfully run build steps like asset bundling, etc. while 
also benefiting from lower slug sizes by removing dependencies that are not required at runtime.
                                     
To avoid modifying the list of installed plugins configured in an application's `.yarnrc.yml` file, 
we include this plugin via the [`YARN_PLUGINS` environment variable](https://yarnpkg.com/advanced/plugin-tutorial#dynamically-loading-plugins-using-the-yarn_plugins-environment-variable).

The plugin adds a single command to Yarn 2 which can be invoked with:

```shell
$ yarn heroku prune
```
       
## Prerequisites
                                                                         
Make sure you have a suitable version of Node installed locally. The test suite relies on 
[`corepack`](https://github.com/nodejs/corepack) to be available so it will need to be enabled or installed as a global package to use.  

Then run: 

```shell
$ corepack enable
$ npm install
```
              
## Build the Plugin

```shell
$ npm run build
```

## Run Tests

```shell
$ npm test
```
