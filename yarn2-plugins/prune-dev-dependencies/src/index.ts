import { Cache, Configuration, Plugin, Project, StreamReport, CommandContext } from '@yarnpkg/core'
import { Command } from 'clipanion'

class HerokuPruneDevDependenciesCommand extends Command<CommandContext> {
  @Command.Path('heroku', 'prune')

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
      await project.install({ cache, report, persistProject: false })
      await project.cacheCleanup({ cache, report })
      await project.persistInstallStateFile()
    })

    return report.exitCode()
  }
}

const plugin: Plugin = {
  commands: [
    HerokuPruneDevDependenciesCommand
  ]
}

export default plugin
