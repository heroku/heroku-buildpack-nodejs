/* eslint-disable */
//prettier-ignore
module.exports = {
name: "@yarnpkg/plugin-prune-dev-dependencies",
factory: function (require) {
"use strict";
var plugin = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __require = /* @__PURE__ */ ((x) => typeof require !== "undefined" ? require : typeof Proxy !== "undefined" ? new Proxy(x, {
    get: (a, b) => (typeof require !== "undefined" ? require : a)[b]
  }) : x)(function(x) {
    if (typeof require !== "undefined")
      return require.apply(this, arguments);
    throw new Error('Dynamic require of "' + x + '" is not supported');
  });
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // src/index.ts
  var src_exports = {};
  __export(src_exports, {
    default: () => src_default
  });
  var import_core = __require("@yarnpkg/core");
  var { Command } = __require("clipanion");
  var HerokuPruneDevDependenciesCommand = class extends Command {
    async execute() {
      const configuration = await import_core.Configuration.find(this.context.cwd, this.context.plugins);
      const { project } = await import_core.Project.find(configuration, this.context.cwd);
      const cache = await import_core.Cache.find(configuration);
      await project.restoreInstallState({
        restoreResolutions: false
      });
      for (const workspace of project.workspaces) {
        workspace.manifest.devDependencies.clear();
      }
      const report = await import_core.StreamReport.start({
        configuration,
        json: false,
        stdout: this.context.stdout,
        includeLogs: true
      }, async (report2) => {
        try {
          await project.install({ cache, report: report2, persistProject: false });
          await project.cacheCleanup({ cache, report: report2 });
          await project.persistInstallStateFile();
        } catch (e) {
          console.warn("[yarn heroku prune] An error occurred while pruning development dependencies from the application!");
          console.error(e);
        }
      });
      return report.exitCode();
    }
  };
  try {
    Command.Path("heroku", "prune")(HerokuPruneDevDependenciesCommand.prototype, "execute");
  } catch {
    try {
      HerokuPruneDevDependenciesCommand.paths = [["heroku", "prune"]];
    } catch (e) {
      console.warn("[yarn heroku prune] An error occurred while configuring the plugin!");
      console.error(e);
    }
  }
  var plugin = {
    commands: [
      HerokuPruneDevDependenciesCommand
    ]
  };
  var src_default = plugin;
  return __toCommonJS(src_exports);
})();
return plugin;
}
};
