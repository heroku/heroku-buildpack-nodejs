# Heroku Node.js Buildpack: Yoga

Preview the next version of the node buildpack: yoga. It's powerful and flexible.

```shell
heroku config:set BUILDPACK_URL=https://github.com/heroku/heroku-buildpack-nodejs#yoga
git commit -am 'yoga' --allow-empty
git push heroku master
```

## What can I do with Yoga?

- Specify a version of npm  with `engines.npm` and avoid those pre-2.0 bugs!
- Set `BUILD_CLEAN` to control `node_modules` caching between deploys
- Set `NPM_CONFIG_PRODUCTION` to control `devDependencies` installation
- Get clean output on success and concise debugging info on failure - no more 20,000-line logs
- Go crazy with `.npmrc` configs
- Export `NODE_HOME` and `PATH` for better integration with multiple buildpacks

## Roadmap

The next features in the pipeline include:

- Specifying io.js as your node engine
- Providing proxy settings for your locked-down enterprise environment

## Feedback

Having trouble? Dig it? Feature request?

- [help.heroku.com](https://help.heroku.com/)
- [@hunterloftis](http://twitter.com/hunterloftis)
- [github issues](https://github.com/heroku/heroku-buildpack-nodejs/issues)

## Testing

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
