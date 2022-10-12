import { spawn } from 'node:child_process'
import { resolve, join } from 'node:path'
import { SpawnOptions } from 'child_process'
import { emptyDir, copy, remove, readdir, readJSON, writeJSON, ensureDir, ensureFile } from 'fs-extra'
import * as path from 'path'

enum Cache {
  LOCAL = 'local',
  GLOBAL = 'global'
}

enum NodeLinker {
  NODE_MODULES = 'node-modules',
  PNP = 'pnp'
}

interface YarnProject {
  projectDir: string
  cacheDir: string
  yarnBin: (...args: string[]) => Promise<SpawnResult>
}

interface SpawnResult {
  exitCode: number
  stdout: string
  stderr: string
}

interface TestConfiguration { yarnVersion: string, cache: Cache, nodeLinker: NodeLinker }

interface ProjectInfo {
  cacheFiles: string[]
  nodeModules: string[]
  binFiles: string[]
}

const rootDir = resolve(__dirname, '..')
const tmpDir = join(rootDir, 'tmp')
const fixturesDir = join(__dirname, 'fixtures')
const pluginBundle = join('..', '..', 'bundles', '@yarnpkg', 'plugin-prune-dev-dependencies.js')
const testMatrix = createMatrix({
  yarnVersion: [
    '2.4.1',
    '3.2.4',
    '4.0.0-rc.22'
  ],
  cache: [
    Cache.LOCAL,
    Cache.GLOBAL
  ],
  nodeLinker: [
    NodeLinker.NODE_MODULES,
    NodeLinker.PNP
  ]
})

// set jest timeout to 30s
jest.setTimeout(60 * 1000)

describe('yarn-plugin-production-install', () => {
  beforeAll(async () => await emptyDir(tmpDir))

  it.each(testMatrix)('should prune dev dependencies (%o)', async (testConfiguration) => {
    const yarnProject = await createYarnProject(testConfiguration)

    await yarnProject.yarnBin('install')

    expect(await readProjectInfo(yarnProject)).toEqual({
      cacheFiles: expect.arrayContaining([
        expect.stringMatching(/^@types-node.*.zip$/),
        expect.stringMatching(/^echo-cli.*.zip$/),
        expect.stringMatching(/^string.fromcodepoint.*.zip$/),
        expect.stringMatching(/^unescape-js.*.zip$/),
        expect.stringMatching(/^uuid.*.zip$/)
      ]),
      nodeModules: testConfiguration.nodeLinker === NodeLinker.NODE_MODULES
        ? [
            '@types/node',
            'echo-cli',
            'string.fromcodepoint',
            'unescape-js',
            'uuid'
          ]
        : [],
      binFiles: testConfiguration.nodeLinker === NodeLinker.NODE_MODULES
        ? [
            'echo-cli',
            'uuid'
          ]
        : []
    })

    await yarnProject.yarnBin('heroku', 'prune')

    expect(await readProjectInfo(yarnProject)).toEqual({
      cacheFiles: expect.arrayContaining([
        expect.stringMatching(/^echo-cli.*.zip$/),
        expect.stringMatching(/^string.fromcodepoint.*.zip$/),
        expect.stringMatching(/^unescape-js.*.zip$/)
      ]),
      nodeModules: testConfiguration.nodeLinker === NodeLinker.NODE_MODULES
        ? [
            'echo-cli',
            'string.fromcodepoint',
            'unescape-js'
          ]
        : [],
      binFiles: testConfiguration.nodeLinker === NodeLinker.NODE_MODULES
        ? [
            'echo-cli'
          ]
        : []
    })

    const { stdout } = await yarnProject.yarnBin('run', 'echo-cli', 'are binary scripts available?')
    expect(stdout.trim()).toBe('are binary scripts available?')
  })
})

async function createYarnProject (options: TestConfiguration): Promise<YarnProject> {
  const fixtureDir = join(fixturesDir, 'basic-yarn-project')
  const projectDir = join(tmpDir, `yarn-v${options.yarnVersion}-${options.cache}-${options.nodeLinker}`)
  const globalFolder = join(projectDir, '.yarn', 'global')

  // setup directory files
  await emptyDir(projectDir)
  await copy(fixtureDir, projectDir)
  await remove(join(projectDir, 'node_modules'))
  await ensureDir(globalFolder)
  await ensureFile(join(projectDir, 'yarn.lock'))

  // configure the version of yarn to use on this run
  const packageJson = await readJSON(join(projectDir, 'package.json'))
  packageJson.packageManager = `yarn@${options.yarnVersion}`
  await writeJSON(join(projectDir, 'package.json'), packageJson, { spaces: 2 })

  // define helper for running yarn from test directory
  const yarnBin = async (...args: string[]): Promise<SpawnResult> => await promiseSpawn('corepack', ['yarn', ...args], {
    cwd: projectDir,
    env: {
      ...process.env,
      YARN_PLUGINS: pluginBundle
    }
  })

  await promiseSpawn('corepack', ['yarn', 'set', 'version', options.yarnVersion], { cwd: projectDir })

  // configure yarn with cache settings for the test
  await yarnBin('config', 'set', 'globalFolder', globalFolder)
  await yarnBin('config', 'set', 'enableGlobalCache', `${options.cache === Cache.GLOBAL ? 'true' : 'false'}`)

  // configure yarn with nodeLinker
  await yarnBin('config', 'set', 'nodeLinker', options.nodeLinker)

  // read the location of the cache from yarn
  const { stdout, exitCode } = await yarnBin('config', 'get', 'cacheFolder', '--json')
  if (exitCode !== 0) {
    throw new Error(`Non-zero exit code (${exitCode})\n${stdout}`)
  }
  const cacheDir = JSON.parse(stdout)

  return {
    projectDir,
    yarnBin,
    cacheDir: path.relative(projectDir, cacheDir)
  }
}

async function promiseSpawn (command: string, args: string[], options: SpawnOptions): Promise<SpawnResult> {
  // this is borrowed from https://github.com/chalk/ansi-regex but jest won't let me import that module
  const ansiRegex = new RegExp([
    '[\\u001B\\u009B][[\\]()#;?]*(?:(?:(?:(?:;[-a-zA-Z\\d\\/#&.:=?%@~_]+)*|[a-zA-Z\\d]+(?:;[-a-zA-Z\\d\\/#&.:=?%@~_]*)*)?\\u0007)',
    '(?:(?:\\d{1,4}(?:;\\d{0,4})*)?[\\dA-PR-TZcf-nq-uy=><~]))'
  ].join('|'), 'g')

  const childProcess = spawn(command, args, options)

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

async function readProjectInfo (yarnProject: YarnProject): Promise<ProjectInfo> {
  const cacheFiles = await readdir(join(yarnProject.projectDir, yarnProject.cacheDir))
  const nodeModules: string[] = []
  const binFiles: string[] = []

  try {
    const nodeModulesDir = join(yarnProject.projectDir, 'node_modules')
    for await (const dir of await readdir(nodeModulesDir)) {
      if (dir === '.bin') {
        for (const bin of await readdir(join(nodeModulesDir, dir))) {
          binFiles.push(bin)
        }
      } else if (dir.startsWith('@')) {
        for (const subdir of await readdir(join(nodeModulesDir, dir))) {
          nodeModules.push(join(dir, subdir))
        }
      } else {
        nodeModules.push(dir)
      }
    }
  } catch (e) {
    // ignore since this should only fail if there are no node_modules
  }

  const excludeDotFiles = (f: string): boolean => !f.startsWith('.')

  return {
    cacheFiles: cacheFiles.filter(excludeDotFiles).sort(),
    nodeModules: nodeModules.filter(excludeDotFiles).sort(),
    binFiles: binFiles.filter(excludeDotFiles).sort()
  }
}

function createMatrix (options: { yarnVersion: string[], cache: Cache[], nodeLinker: NodeLinker[] }): TestConfiguration[] {
  const matrix: TestConfiguration[] = []
  for (const yarnVersion of options.yarnVersion) {
    for (const cache of options.cache) {
      for (const nodeLinker of options.nodeLinker) {
        matrix.push({ yarnVersion, cache, nodeLinker })
      }
    }
  }
  return matrix
}
