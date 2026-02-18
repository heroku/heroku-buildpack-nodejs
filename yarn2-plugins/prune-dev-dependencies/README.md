# Yarn v2 Plugin: Prune devDependencies

Unlike Yarn 1 and npm, Yarn 2/3/4 doesn't support pruning `devDependencies` as a direct command. This project adds a custom plugin to be included in builds using Yarn 2+ to 
restore this functionality.

> [!NOTE]
> Yarn 4 does support an indirect form of pruning with it's built-in [workspaces focus](https://yarnpkg.com/cli/workspaces/focus)
> command but this won't remove dev dependencies in pnp-mode. For this reason, the plugin here is more suitable for 
> producing minimal slug sizes across different Yarn configurations.
              
The default handling of dependencies for package managers in Heroku's Node.js buildpacks is:
* install all dependencies
* run pre-build and post-build scripts
* remove development dependencies that have been installed

This allows an application to successfully run build steps like asset bundling, etc. while 
also benefiting from lower slug sizes by removing dependencies that are not required at runtime.
                                     
To avoid modifying the list of installed plugins configured in an application's `.yarnrc.yml` file, 
we include this plugin via the [`YARN_PLUGINS` environment variable](https://yarnpkg.com/advanced/plugin-tutorial#dynamically-loading-plugins-using-the-yarn_plugins-environment-variable).

The plugin adds a single command to Yarn 2+ which can be invoked with:

```shell
$ yarn heroku prune
```
       
## Prerequisites
                                                                         
Make sure you have a suitable LTS version of Node installed locally. The test suite relies on 
[`corepack`](https://github.com/nodejs/corepack) to be available so it will need to be enabled or installed as a global package to use.  

Then run: 

```shell
$ corepack enable
$ npm install
```
              
## Build the Plugin

> [!IMPORTANT]
> This plugin targets a Node.js version of 12+ which will be produced by the TypeScript compilation 
> target configuration of `ES2019`. This should ensure compatiblity with minimum Node.js requirements
> from Yarn 2 onwards.

```shell
$ npm run build
```

## Run Tests

The test suite executes a matrix of the following Yarn versions and configuration properties:

```yaml
yarnVersion: ['2.4.1', '3.8.6', '4.5.3']
cache: ['local', 'global']
nodeLinker: ['node-modules', 'pnp']
```

```shell
$ npm test
```
