require_relative '../spec_helper'

describe "pnpm support" do
  it "should successfully deploy a pnpm workspace with pruned devDependencies" do
    app = Hatchet::Runner.new("spec/fixtures/repos/pnpm-workspace")
    app.deploy do |app|
      expect(clean_output(app.output)).to match(Regexp.new(<<~'REGEX'))
        remote: -----> Installing binaries
        remote:        engines\.node \(package\.json\):   unspecified
        remote:        engines\.npm \(package\.json\):    unspecified \(use default\)
        remote:        engines\.pnpm \(package\.json\):   unspecified \(use default\)
        remote:        packageManager \(package\.json\): pnpm@9\.5\.0
        remote:
        remote:        No Node\.js version specified, resolving current LTS version\.\.\.
        remote:        Downloading and installing node .+\.\.\.
        remote:        Validating checksum
        remote:        Using default npm version: .+
        remote:        Downloading and installing pnpm \(9\.5\.0\)
        remote:        Using pnpm 9\..+
      REGEX
      expect(app.output).to include("Running 'pnpm install' with pnpm-lock.yaml")
      expect(app.output).not_to include("pnpm store cache may not work")
      expect(app.output).to include("Pruning devDependencies")
      expect(app.output).to include("devDependencies: skipped because NODE_ENV is set to production")
      expect(successful_body(app).strip).to eq("Hello from pnpm workspace")

      # Rebuild to test cache restoration and pruning still works
      run!('git commit --allow-empty -m "rebuild to test caching"')
      app.push!

      # Second deploy should restore cache and prune again
      expect(app.output).to include("Restoring cache")
      expect(app.output).to include("- pnpm cache")
      expect(app.output).to include("Running 'pnpm install' with pnpm-lock.yaml")
      expect(app.output).not_to include("pnpm store cache may not work")
      expect(app.output).to include("Pruning devDependencies")
      expect(app.output).to include("devDependencies: skipped because NODE_ENV is set to production")
      expect(successful_body(app).strip).to eq("Hello from pnpm workspace")
    end
  end

  it "should successfully deploy a pnpm 10 app" do
    app = Hatchet::Runner.new("spec/fixtures/repos/pnpm-10")
    app.deploy do |app|
      expect(clean_output(app.output)).to match(Regexp.new(<<~'REGEX'))
        remote: -----> Installing binaries
        remote:        engines\.node \(package\.json\):   22\.x
        remote:        engines\.npm \(package\.json\):    unspecified \(use default\)
        remote:        engines\.pnpm \(package\.json\):   unspecified \(use default\)
        remote:        packageManager \(package\.json\): pnpm@10\.0\.0
        remote:
        remote:        Resolving node version 22\.x\.\.\.
        remote:        Downloading and installing node .+\.\.\.
        remote:        Validating checksum
        remote:        Using default npm version: .+
        remote:        Downloading and installing pnpm \(10\.0\.0\)
        remote:        Using pnpm 10\..+
      REGEX
      expect(app.output).to include("Running 'pnpm install' with pnpm-lock.yaml")
      expect(app.output).not_to include("pnpm store cache may not work")
      expect(app.output).to include("Pruning devDependencies")
      expect(successful_body(app).strip).to eq("Hello from pnpm 10")

      # Rebuild to test cache restoration and pruning still works
      run!('git commit --allow-empty -m "rebuild to test caching"')
      app.push!

      expect(app.output).to include("Restoring cache")
      expect(app.output).to include("Running 'pnpm install' with pnpm-lock.yaml")
      expect(app.output).not_to include("pnpm store cache may not work")
      expect(app.output).to include("Pruning devDependencies")
      expect(successful_body(app).strip).to eq("Hello from pnpm 10")
    end
  end

  it "should successfully deploy a pnpm 10 workspace" do
    app = Hatchet::Runner.new("spec/fixtures/repos/pnpm-10-workspace")
    app.deploy do |app|
      expect(clean_output(app.output)).to match(Regexp.new(<<~'REGEX'))
        remote: -----> Installing binaries
        remote:        engines\.node \(package\.json\):   22\.x
        remote:        engines\.npm \(package\.json\):    unspecified \(use default\)
        remote:        engines\.pnpm \(package\.json\):   unspecified \(use default\)
        remote:        packageManager \(package\.json\): pnpm@10\.0\.0
        remote:
        remote:        Resolving node version 22\.x\.\.\.
        remote:        Downloading and installing node .+\.\.\.
        remote:        Validating checksum
        remote:        Using default npm version: .+
        remote:        Downloading and installing pnpm \(10\.0\.0\)
        remote:        Using pnpm 10\..+
      REGEX
      expect(app.output).to include("Running 'pnpm install' with pnpm-lock.yaml")
      expect(app.output).not_to include("pnpm store cache may not work")
      expect(app.output).to include("Pruning devDependencies")
      expect(successful_body(app).strip).to eq("Hello from pnpm 10 workspace")

      # Rebuild to test cache restoration
      run!('git commit --allow-empty -m "rebuild to test caching"')
      app.push!

      expect(app.output).to include("Restoring cache")
      expect(app.output).to include("Running 'pnpm install' with pnpm-lock.yaml")
      expect(app.output).not_to include("pnpm store cache may not work")
      expect(successful_body(app).strip).to eq("Hello from pnpm 10 workspace")
    end
  end

  it "should successfully deploy a pnpm 11 app" do
    app = Hatchet::Runner.new("spec/fixtures/repos/pnpm-11")
    app.deploy do |app|
      expect(clean_output(app.output)).to match(Regexp.new(<<~'REGEX'))
        remote: -----> Installing binaries
        remote:        engines\.node \(package\.json\):   22\.x
        remote:        engines\.npm \(package\.json\):    unspecified \(use default\)
        remote:        engines\.pnpm \(package\.json\):   unspecified \(use default\)
        remote:        packageManager \(package\.json\): pnpm@11\.0\.0
        remote:
        remote:        Resolving node version 22\.x\.\.\.
        remote:        Downloading and installing node .+\.\.\.
        remote:        Validating checksum
        remote:        Using default npm version: .+
        remote:        Downloading and installing pnpm \(11\.0\.0\)
        remote:        Using pnpm 11\..+
      REGEX
      expect(app.output).to include("Running 'pnpm install' with pnpm-lock.yaml")
      expect(app.output).not_to include("pnpm store cache may not work")
      expect(app.output).to include("Pruning devDependencies")
      expect(successful_body(app).strip).to eq("Hello from pnpm 11")

      # Rebuild to test cache restoration and pruning still works
      run!('git commit --allow-empty -m "rebuild to test caching"')
      app.push!

      expect(app.output).to include("Restoring cache")
      expect(app.output).to include("Running 'pnpm install' with pnpm-lock.yaml")
      expect(app.output).not_to include("pnpm store cache may not work")
      expect(app.output).to include("Pruning devDependencies")
      expect(successful_body(app).strip).to eq("Hello from pnpm 11")
    end
  end

  it "should successfully deploy a pnpm 11 workspace" do
    app = Hatchet::Runner.new("spec/fixtures/repos/pnpm-11-workspace")
    app.deploy do |app|
      expect(clean_output(app.output)).to match(Regexp.new(<<~'REGEX'))
        remote: -----> Installing binaries
        remote:        engines\.node \(package\.json\):   22\.x
        remote:        engines\.npm \(package\.json\):    unspecified \(use default\)
        remote:        engines\.pnpm \(package\.json\):   unspecified \(use default\)
        remote:        packageManager \(package\.json\): pnpm@11\.0\.0
        remote:
        remote:        Resolving node version 22\.x\.\.\.
        remote:        Downloading and installing node .+\.\.\.
        remote:        Validating checksum
        remote:        Using default npm version: .+
        remote:        Downloading and installing pnpm \(11\.0\.0\)
        remote:        Using pnpm 11\..+
      REGEX
      expect(app.output).to include("Running 'pnpm install' with pnpm-lock.yaml")
      expect(app.output).not_to include("pnpm store cache may not work")
      expect(app.output).to include("Pruning devDependencies")
      expect(successful_body(app).strip).to eq("Hello from pnpm 11 workspace")

      # Rebuild to test cache restoration
      run!('git commit --allow-empty -m "rebuild to test caching"')
      app.push!

      expect(app.output).to include("Restoring cache")
      expect(app.output).to include("Running 'pnpm install' with pnpm-lock.yaml")
      expect(app.output).not_to include("pnpm store cache may not work")
      expect(successful_body(app).strip).to eq("Hello from pnpm 11 workspace")
    end
  end

  # Regression test for W-22952473.
  #
  # pnpm 11 defaults `verify-deps-before-run` to `install`, so any `pnpm run`
  # (including `pnpm start`) first checks whether `node_modules` is in sync with
  # the lockfile. That check keys on the absolute project paths recorded in
  # `node_modules/.pnpm-workspace-state-v1.json` at install time. The classic
  # buildpack installs in `/tmp/build_<hash>` but the app runs from `/app`, so
  # every workspace project lookup misses, pnpm decides the "workspace structure
  # has changed", and runs a nested `pnpm install` at boot. In the non-TTY dyno
  # environment that install aborts with
  # `ERR_PNPM_ABORTED_REMOVE_MODULES_DIR_NO_TTY` and the process crashes.
  #
  # NODE_ENV is deliberately not "production" so devDependency pruning is skipped
  # (matching the reported app), proving the crash originates from the initial
  # install's workspace-state file rather than from the prune step.
  it "starts a pnpm 11 workspace web process that runs through pnpm" do
    app = Hatchet::Runner.new(
      "spec/fixtures/repos/pnpm-11-verify-deps",
      stack: "heroku-24",
      config: { "NODE_ENV" => "staging" }
    )
    app.deploy do |app|
      expect(app.output).to include("Running 'pnpm install' with pnpm-lock.yaml")
      expect(app.output).to include("Skipping because NODE_ENV is not 'production'")
      # The web process is `pnpm --filter=server start`. If the runtime deps
      # check misfires it shells out to `pnpm install`, which aborts in the
      # non-TTY dyno with ERR_PNPM_ABORTED_REMOVE_MODULES_DIR_NO_TTY and the
      # dyno crashes before serving a response.
      # lodash's `_.capitalize` upper-cases the first letter: "Pnpm ...".
      expect(successful_body(app).strip).to eq("Hello from Pnpm 11 workspace")
    end
  end
end
