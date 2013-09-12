## Testing buildpack changes using Anvil

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

## Publishing buildpack updates

```
heroku plugins:install https://github.com/heroku/heroku-buildpacks

cd heroku-buildpack-nodejs
git checkout master
heroku buildpacks:publish heroku/nodejs
```

- Email [dos@heroku.com](mailto:dos@heroku.com) if changes are significant.
- Add a [changelog item](https://devcenter.heroku.com/admin/changelog_items/new).
- Update [Node Devcenter articles](https://devcenter.heroku.com/admin/articles/owned) as necessary.

## Keeping up with the Nodeses

- Run `npm info npm version` to find out the latest available version of npm.
- Follow [@nodejs](https://twitter.com/nodejs) and [@npmjs](https://twitter.com/npmjs) on Twitter.
- Find node-npm version pairings at [nodejs.org/dist/npm-versions.txt](http://nodejs.org/dist/npm-versions.txt)
