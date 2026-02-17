import { Cache, type CommandContext, Configuration, type Plugin, Project, StreamReport } from '@yarnpkg/core'
import { Command } from 'clipanion'

class HerokuPruneDevDependenciesCommand extends Command<CommandContext> {
  async execute(): Promise<number> {
    const configuration = await Configuration.find(this.context.cwd, this.context.plugins)
    const { project } = await Project.find(configuration, this.context.cwd)
    const cache = await Cache.find(configuration)

    await project.restoreInstallState({
      restoreResolutions: false
    })

    for (const workspace of project.workspaces) {
      workspace.manifest.devDependencies.clear()
    }

    const report = await StreamReport.start(
      {
        configuration,
        json: false,
        stdout: this.context.stdout,
        includeLogs: true
      },
      async (report: StreamReport) => {
        try {
          await project.install({ cache, report, persistProject: false })
          await project.cacheCleanup({ cache, report })
          await project.persistInstallStateFile()
        } catch (e) {
          console.warn(
            '[yarn heroku prune] An error occurred while pruning development dependencies from the application!'
          )
          console.error(e)
        }
      }
    )

    return report.exitCode()
  }
}

try {
  // Yarn 2 & 3 require the decorator-style registration
  // @ts-expect-error - Command.Path exists at runtime in older Clipanion versions bundled with Yarn 2/3
  Command.Path('heroku', 'prune')(HerokuPruneDevDependenciesCommand.prototype, 'execute')
} catch {
  try {
    // Yarn 4 uses static paths property instead
    HerokuPruneDevDependenciesCommand.paths = [['heroku', 'prune']]
  } catch (e) {
    console.warn('[yarn heroku prune] An error occurred while configuring the plugin!')
    console.error(e)
  }
}

const plugin: Plugin = {
  // @ts-expect-error - Command class has required properties that are initialized at runtime by Clipanion
  commands: [HerokuPruneDevDependenciesCommand]
}

export default plugin
