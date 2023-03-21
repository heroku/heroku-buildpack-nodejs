import {
  Cache,
  Configuration,
  Plugin,
  Project,
  StreamReport,
  CommandContext
} from '@yarnpkg/core'
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { Command } = require('clipanion')

class HerokuPruneDevDependenciesCommand extends Command<CommandContext> {
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

try {
  // Yarn 2 & 3 and below work with the annotation, so we'll add it.
  Command.Path('heroku', 'prune')(HerokuPruneDevDependenciesCommand.prototype, 'execute')
} catch {
  try {
    // Yarn 4 doesn't provide the compatibility layer for the old Clipanion annotation (`@Command.Path()`), so we need to add paths.
    HerokuPruneDevDependenciesCommand.paths = [['heroku', 'prune']]
  } catch (e) {
    console.warn('[yarn heroku prune] An error occurred while configuring the plugin!')
    console.error(e)
  }
}

const plugin: Plugin = {
  commands: [
    HerokuPruneDevDependenciesCommand
  ]
}

export default plugin
