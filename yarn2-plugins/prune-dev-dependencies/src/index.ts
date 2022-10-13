import {
  Cache,
  Configuration,
  Plugin,
  Project,
  StreamReport,
  CommandContext,
  YarnVersion
} from '@yarnpkg/core'
import { decorateClass } from './utils'

// eslint-disable-next-line @typescript-eslint/no-var-requires
const clipanion = require('clipanion')
const version = YarnVersion ?? '0.0.0'
const YARN_4 = /^4\./.test(version)

class HerokuPruneDevDependenciesCommand extends clipanion.Command<CommandContext> {
  async execute (): Promise<number> {
    const configuration = await Configuration.find(this.context.cwd, this.context.plugins)
    const { project } = await Project.find(configuration, this.context.cwd)
    const cache = await Cache.find(configuration)

    await project.restoreInstallState({
      restoreResolutions: false
    })

    for (const workspace of project.workspaces) {
      workspace.manifest.devDependencies.clear()
    }

    const report = await StreamReport.start({
      configuration,
      json: false,
      stdout: this.context.stdout,
      includeLogs: true
    }, async (report: StreamReport) => {
      try {
        await project.install({ cache, report, persistProject: false })
        await project.cacheCleanup({ cache, report })
        await project.persistInstallStateFile()
      } catch (e) {
        console.warn('[yarn heroku prune] An error occurred while pruning development dependencies from the application!')
        console.error(e)
      }
    })

    return report.exitCode()
  }
}

if (YARN_4) {
  // Yarn 4 and above don't provide the compatibility layer for the old
  // Clipanion annotation (`@Command.Path()`), so we need to add paths.
  HerokuPruneDevDependenciesCommand.paths = [
    ['heroku', 'prune']
  ]
} else {
  // Yarn 3 and below work with the annotation, so we'll add it.
  decorateClass([
    clipanion.Command.Path('heroku', 'prune')
  ], HerokuPruneDevDependenciesCommand.prototype, 'execute')
}

const plugin: Plugin = {
  commands: [
    HerokuPruneDevDependenciesCommand
  ]
}

export default plugin
