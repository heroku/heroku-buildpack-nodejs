import { spawn } from 'node:child_process'
import { resolve, join } from 'node:path'
import { SpawnOptions } from 'child_process'
import { emptyDir, copy, remove, readdir, pathExists } from 'fs-extra'

const rootDir = resolve(__dirname, '..')
const tmpDir = join(rootDir, 'tmp')
const fixturesDir = join(__dirname, 'fixtures')
const relativePluginPath = join('..', '..', 'bundles', '@yarnpkg', 'plugin-prune-dev-dependencies.js')
const yarnCache = join('.yarn', 'cache')
const nodeModules = join('node_modules')
const nodeModulesBin = join(nodeModules, '.bin')

describe('yarn-plugin-production-install', () => {
  beforeAll(async () => await emptyDir(tmpDir))

  it('should prune dev dependencies from yarn 2 project using node modules linker', async () => {
    const yarnProject = await createYarnProject({
      fixture: 'using-node-modules-linker'
    })

    await yarnProject.yarnBin(['install', '--immutable'])

    await expectProjectIncludesFiles(yarnProject, [
      `${yarnCache}/@types-node-npm-16.11.26-6163d95b7d-57757caaba.zip`,
      `${yarnCache}/echo-cli-npm-2.0.0-b40e6b6835-81a056580e.zip`,
      `${yarnCache}/string.fromcodepoint-npm-0.2.1-84d94c4fb5-6ba80f70c3.zip`,
      `${yarnCache}/typescript-npm-4.6.3-1493ebc82b-255bb26c8c.zip`,
      `${yarnCache}/typescript-patch-30b732d1e2-6bf45caf84.zip`,
      `${yarnCache}/unescape-js-npm-1.1.4-f41cc6935a-97acf60a8f.zip`,
      `${nodeModules}/@types/node`,
      `${nodeModules}/echo-cli`,
      `${nodeModules}/typescript`,
      `${nodeModules}/string.fromcodepoint`,
      `${nodeModules}/unescape-js`,
      `${nodeModulesBin}/echo-cli`,
      `${nodeModulesBin}/tsc`,
      `${nodeModulesBin}/tsserver`
    ])

    await yarnProject.yarnBin(['heroku', 'prune'])

    await expectProjectIncludesFiles(yarnProject, [
      `${yarnCache}/echo-cli-npm-2.0.0-b40e6b6835-81a056580e.zip`,
      `${yarnCache}/string.fromcodepoint-npm-0.2.1-84d94c4fb5-6ba80f70c3.zip`,
      `${yarnCache}/unescape-js-npm-1.1.4-f41cc6935a-97acf60a8f.zip`,
      `${nodeModules}/echo-cli`,
      `${nodeModules}/string.fromcodepoint`,
      `${nodeModules}/unescape-js`,
      `${nodeModulesBin}/echo-cli`
    ])

    await expectProjectDoesNotIncludeFiles(yarnProject, [
      `${yarnCache}/@types-node-npm-16.11.26-6163d95b7d-57757caaba.zip`,
      `${yarnCache}/typescript-npm-4.6.3-1493ebc82b-255bb26c8c.zip`,
      `${yarnCache}/typescript-patch-30b732d1e2-6bf45caf84.zip`,
      `${nodeModules}/@types/node`,
      `${nodeModules}/typescript`,
      `${nodeModulesBin}/tsc`,
      `${nodeModulesBin}/tsserver`
    ])
  })

  it('should prune dev dependencies from yarn 2 project using node modules linker when some cached dependencies are missing', async () => {
    const yarnProject = await createYarnProject({
      fixture: 'using-node-modules-linker'
    })

    await remove(`${yarnCache}/echo-cli-npm-2.0.0-b40e6b6835-81a056580e.zip`)

    await yarnProject.yarnBin(['install', '--immutable'])

    await expectProjectIncludesFiles(yarnProject, [
      `${yarnCache}/@types-node-npm-16.11.26-6163d95b7d-57757caaba.zip`,
      `${yarnCache}/echo-cli-npm-2.0.0-b40e6b6835-81a056580e.zip`,
      `${yarnCache}/string.fromcodepoint-npm-0.2.1-84d94c4fb5-6ba80f70c3.zip`,
      `${yarnCache}/typescript-npm-4.6.3-1493ebc82b-255bb26c8c.zip`,
      `${yarnCache}/typescript-patch-30b732d1e2-6bf45caf84.zip`,
      `${yarnCache}/unescape-js-npm-1.1.4-f41cc6935a-97acf60a8f.zip`,
      `${nodeModules}/@types/node`,
      `${nodeModules}/echo-cli`,
      `${nodeModules}/typescript`,
      `${nodeModules}/string.fromcodepoint`,
      `${nodeModules}/unescape-js`,
      `${nodeModulesBin}/echo-cli`,
      `${nodeModulesBin}/tsc`,
      `${nodeModulesBin}/tsserver`
    ])

    await yarnProject.yarnBin(['heroku', 'prune'])

    await expectProjectIncludesFiles(yarnProject, [
      `${yarnCache}/echo-cli-npm-2.0.0-b40e6b6835-81a056580e.zip`,
      `${yarnCache}/string.fromcodepoint-npm-0.2.1-84d94c4fb5-6ba80f70c3.zip`,
      `${yarnCache}/unescape-js-npm-1.1.4-f41cc6935a-97acf60a8f.zip`,
      `${nodeModules}/echo-cli`,
      `${nodeModules}/string.fromcodepoint`,
      `${nodeModules}/unescape-js`,
      `${nodeModulesBin}/echo-cli`
    ])

    await expectProjectDoesNotIncludeFiles(yarnProject, [
      `${yarnCache}/@types-node-npm-16.11.26-6163d95b7d-57757caaba.zip`,
      `${yarnCache}/typescript-npm-4.6.3-1493ebc82b-255bb26c8c.zip`,
      `${yarnCache}/typescript-patch-30b732d1e2-6bf45caf84.zip`,
      `${nodeModules}/@types/node`,
      `${nodeModules}/typescript`,
      `${nodeModulesBin}/tsc`,
      `${nodeModulesBin}/tsserver`
    ])
  })

  it('should prune dev dependencies from yarn 2 project using pnp linker', async () => {
    const yarnProject = await createYarnProject({
      fixture: 'using-pnp-linker'
    })

    await yarnProject.yarnBin(['install', '--immutable'])

    await expectProjectIncludesFiles(yarnProject, [
      `${yarnCache}/@types-node-npm-16.11.26-6163d95b7d-57757caaba.zip`,
      `${yarnCache}/echo-cli-npm-2.0.0-b40e6b6835-81a056580e.zip`,
      `${yarnCache}/string.fromcodepoint-npm-0.2.1-84d94c4fb5-6ba80f70c3.zip`,
      `${yarnCache}/typescript-npm-4.6.3-1493ebc82b-255bb26c8c.zip`,
      `${yarnCache}/typescript-patch-30b732d1e2-6bf45caf84.zip`,
      `${yarnCache}/unescape-js-npm-1.1.4-f41cc6935a-97acf60a8f.zip`
    ])

    await yarnProject.yarnBin(['heroku', 'prune'])

    await expectProjectIncludesFiles(yarnProject, [
      `${yarnCache}/echo-cli-npm-2.0.0-b40e6b6835-81a056580e.zip`,
      `${yarnCache}/string.fromcodepoint-npm-0.2.1-84d94c4fb5-6ba80f70c3.zip`,
      `${yarnCache}/unescape-js-npm-1.1.4-f41cc6935a-97acf60a8f.zip`
    ])

    const { stdout } = await yarnProject.yarnBin(['run', 'echo'])
    expect(stdout.trim()).toBe('production dependency binary works!')
  })

  it('should prune dev dependencies from yarn 2 project using pnp linker when some cached dependencies are missing', async () => {
    const yarnProject = await createYarnProject({
      fixture: 'using-pnp-linker'
    })

    await remove(`${yarnCache}/echo-cli-npm-2.0.0-b40e6b6835-81a056580e.zip`)

    await yarnProject.yarnBin(['install', '--immutable'])

    await expectProjectIncludesFiles(yarnProject, [
      `${yarnCache}/@types-node-npm-16.11.26-6163d95b7d-57757caaba.zip`,
      `${yarnCache}/echo-cli-npm-2.0.0-b40e6b6835-81a056580e.zip`,
      `${yarnCache}/string.fromcodepoint-npm-0.2.1-84d94c4fb5-6ba80f70c3.zip`,
      `${yarnCache}/typescript-npm-4.6.3-1493ebc82b-255bb26c8c.zip`,
      `${yarnCache}/typescript-patch-30b732d1e2-6bf45caf84.zip`,
      `${yarnCache}/unescape-js-npm-1.1.4-f41cc6935a-97acf60a8f.zip`
    ])

    await yarnProject.yarnBin(['heroku', 'prune'])

    await expectProjectIncludesFiles(yarnProject, [
      `${yarnCache}/echo-cli-npm-2.0.0-b40e6b6835-81a056580e.zip`,
      `${yarnCache}/string.fromcodepoint-npm-0.2.1-84d94c4fb5-6ba80f70c3.zip`,
      `${yarnCache}/unescape-js-npm-1.1.4-f41cc6935a-97acf60a8f.zip`
    ])

    const { stdout } = await yarnProject.yarnBin(['run', 'echo'])
    expect(stdout.trim()).toBe('production dependency binary works!')
  })
})

interface YarnProject {
  projectDir: string
  cacheFiles: Promise<string[]>
  yarnBin: (args: string[]) => Promise<SpawnResult>
}

async function createYarnProject (options: { fixture: string }): Promise<YarnProject> {
  const fixtureDir = join(fixturesDir, options.fixture)
  const projectDir = join(tmpDir, options.fixture)
  const cacheDir = join(projectDir, '.yarn', 'cache')

  const yarnBinOptions = {
    cwd: projectDir,
    env: { ...process.env, YARN_PLUGINS: relativePluginPath }
  }

  await emptyDir(projectDir)
  await copy(fixtureDir, projectDir)
  await remove(join(projectDir, 'node_modules'))

  return {
    projectDir,
    get cacheFiles () {
      return readdir(cacheDir)
    },
    async yarnBin (args: string[]) {
      return await promiseSpawn('corepack', args, yarnBinOptions)
    }
  }
}

interface SpawnResult {
  exitCode: number
  stdout: string
  stderr: string
}

async function promiseSpawn (command: string, args: string[], options: SpawnOptions): Promise<SpawnResult> {
  // this is borrowed from https://github.com/chalk/ansi-regex but jest won't let me import that module
  const ansiRegex = new RegExp([
    '[\\u001B\\u009B][[\\]()#;?]*(?:(?:(?:(?:;[-a-zA-Z\\d\\/#&.:=?%@~_]+)*|[a-zA-Z\\d]+(?:;[-a-zA-Z\\d\\/#&.:=?%@~_]*)*)?\\u0007)',
    '(?:(?:\\d{1,4}(?:;\\d{0,4})*)?[\\dA-PR-TZcf-nq-uy=><~]))'
  ].join('|'), 'g')

  const childProcess = spawn('corepack', ['yarn', ...args], options)

  let stdout = ''
  childProcess.stdout?.on('data', (data) => {
    if (Buffer.isBuffer(data)) {
      const noAnsiOutput = data.toString().replace(ansiRegex, '')
      stdout += noAnsiOutput
      process.stdout.write(noAnsiOutput)
    }
  })

  let stderr = ''
  childProcess.stderr?.on('data', (data) => {
    if (Buffer.isBuffer(data)) {
      const noAnsiOutput = data.toString().replace(ansiRegex, '')
      stderr += noAnsiOutput
      process.stderr.write(noAnsiOutput)
    }
  })

  return await new Promise((resolve) => {
    childProcess.on('close', (exitCode) => {
      exitCode = exitCode ?? -1
      process.stdout.write('\n')
      resolve({ exitCode, stdout, stderr })
    })
  })
}

async function expectProjectIncludesFiles (yarnProject: YarnProject, paths: string[]): Promise<void> {
  const includedPaths = []
  for await (const path of paths) {
    const exists = await pathExists(join(yarnProject.projectDir, path))
    if (exists) {
      includedPaths.push(path)
    }
  }
  expect(includedPaths).toEqual(paths)
}

async function expectProjectDoesNotIncludeFiles (yarnProject: YarnProject, paths: string[]): Promise<void> {
  const notIncludedPaths = []
  for await (const path of paths) {
    const exists = await pathExists(join(yarnProject.projectDir, path))
    if (!exists) {
      notIncludedPaths.push(path)
    }
  }
  expect(notIncludedPaths).toEqual(paths)
}
