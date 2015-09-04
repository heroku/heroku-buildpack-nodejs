#!/usr/bin/env coffee
#
# NOTE: this script should have *no* dependencies on thirdparty node_modules.
# ALSO: don't forget to recompile this before you push: npm test
#

fs = require 'fs'
path = require 'path'
{spawn} = require 'child_process'

buildPrunedShrinkwrap = ->
  {devDependencies} = JSON.parse fs.readFileSync('./package.json')
  shrinkwrap = JSON.parse fs.readFileSync('./npm-shrinkwrap.json')

  prunedShrinkwrapDependencies = {}
  for name, config of shrinkwrap.dependencies when !devDependencies[name]
    prunedShrinkwrapDependencies[name] = config

  shrinkwrap.dependencies = prunedShrinkwrapDependencies

  return shrinkwrap

commands =

  prune: (shrinkwrap, cb) ->
    try
      moduleDirs = fs.readdirSync './node_modules'
    catch e
      throw e unless e.code is 'ENOENT'
      return process.nextTick(cb)

    modulesToPrune = (dir for dir in moduleDirs when dir[0] isnt '.' and !shrinkwrap.dependencies[dir])
    npm = spawn 'npm', ['rm', process.argv[3..]..., modulesToPrune...], {stdio: 'inherit'}
    npm.on 'close', (code) ->
      cb code isnt 0 and new Error("non-zero exit code #{code}") or null

  install: (shrinkwrap, cb) ->
    cleanup = ->
      try
        console.log 'restoring original npm-shrinkwrap.json'
        fs.renameSync './.full-npm-shrinkwrap.json', './npm-shrinkwrap.json'
      catch e
        # swallow errors

    fs.writeFileSync './.pruned-npm-shrinkwrap.json', JSON.stringify(shrinkwrap, null, '  ')
    fs.renameSync './npm-shrinkwrap.json', './.full-npm-shrinkwrap.json'

    console.log 'installing pruned npm-shrinkwrap.json\n'
    fs.renameSync './.pruned-npm-shrinkwrap.json', './npm-shrinkwrap.json'

    try
      npm = spawn 'npm', ['install', process.argv[3..]...], {stdio: 'inherit'}
      npm.on 'close', (code) ->
        cleanup()
        cb code isnt 0 and new Error("non-zero exit code #{code}") or null
    catch e
      cleanup()
      throw e


### MAIN ###

command = process.argv[2]?.toLowerCase()

if command in ['prune', 'install'] \
  and fs.existsSync('./package.json') \
  and fs.existsSync('./npm-shrinkwrap.json')
    console.log "npm-production is handling `npm #{command}`"
    shrinkwrap = buildPrunedShrinkwrap()
    commands[command] shrinkwrap, (err) ->
      console.error(err.stack ? err) if err?
      process.exit err? and 1 or 0
  
else
  # passthru
  npm = spawn 'npm', process.argv[2..], {stdio: 'inherit'}
  npm.on 'close', (code) ->
    process.exit code

