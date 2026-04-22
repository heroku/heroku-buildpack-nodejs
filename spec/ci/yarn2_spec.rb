require_relative '../spec_helper'

describe "yarn2 examples" do
  # Example uses the pnp linker and pushes all dependencies in .yarn/cache.
  # No packages should be downloaded and buildcache is not used in this mode.
  it "pnp zero-install with should deploy successfully and not use the cache" do
    app = Hatchet::Runner.new("spec/fixtures/repos/yarn2-pnp-zero-install")
    app.deploy do |app|
      expect(clean_output(app.output)).to match(Regexp.new(<<~'REGEX'))
        remote: -----> Installing binaries
        remote:        engines\.node \(package\.json\):   unspecified
        remote:        engines\.npm \(package\.json\):    unspecified \(use default\)
        remote:        engines\.yarn \(package\.json\):   unspecified \(use default\)
        remote:        packageManager \(package\.json\): yarn@3\.1\.1
        remote:
        remote:         !     Yarn release script may conflict with "packageManager"
        remote:
        remote:               The package\.json file indicates the target version of Yarn to install with:
        remote:               - "packageManager": "yarn@3\.1\.1"
        remote:
        remote:               But the \.yarnrc\.yml configuration indicates a vendored release of Yarn should be used with:
        remote:               - yarnPath: "\.yarn/releases/yarn-3\.1\.1\.cjs"
        remote:
        remote:               This will cause the buildpack to install yarn@3\.1\.1 but, when running Yarn commands, the vendored release
        remote:               at "\.yarn/releases/yarn-3\.1\.1\.cjs" will be executed instead\.
        remote:
        remote:               To ensure we install the version of Yarn you want, choose only one of the following actions:
        remote:               - Remove the "packageManager" field from package\.json
        remote:               - Remove the "yarnPath" configuration from \.yarnrc\.yml and delete the vendored release at "\.yarn/releases/yarn-3\.1\.1\.cjs"
        remote:               https://devcenter\.heroku\.com/articles/nodejs-support
        remote:
        remote:        No Node\.js version specified, resolving current LTS version\.\.\.
        remote:        Downloading and installing node .+\.\.\.
        remote:        Validating checksum
        remote:        Using default npm version: .+
        remote:        Downloading and installing yarn \(1\.22\.x\)
        remote:        Using yarn .+
      REGEX
      expect(successful_body(app).strip).to eq("Hello from yarn2-pnp-zero-install")

      run!('git commit --allow-empty -m "deploy again to test cache reuse"')
      app.push!

      expect(app.output).to include("yarn cache is checked into source control and cannot be cached")
      expect(successful_body(app).strip).to eq("Hello from yarn2-pnp-zero-install")
    end
  end

  # Example uses the pnp linker but does not push dependencies in .yarn/cache.
  # All packages will either be restored from buildcache or downloaded.
  it "pnp nonzero-install should deploy successfully and reuse the cache" do
    app = Hatchet::Runner.new("spec/fixtures/repos/yarn2-pnp-nonzero-install")
    app.deploy do |app|
      expect(clean_output(app.output)).to match(Regexp.new(<<~'REGEX'))
        remote: -----> Installing binaries
        remote:        engines\.node \(package\.json\):   unspecified
        remote:        engines\.npm \(package\.json\):    unspecified \(use default\)
        remote:        engines\.yarn \(package\.json\):   unspecified \(use default\)
        remote:        packageManager \(package\.json\): yarn@3\.1\.1
        remote:
        remote:         !     Yarn release script may conflict with "packageManager"
        remote:
        remote:               The package\.json file indicates the target version of Yarn to install with:
        remote:               - "packageManager": "yarn@3\.1\.1"
        remote:
        remote:               But the \.yarnrc\.yml configuration indicates a vendored release of Yarn should be used with:
        remote:               - yarnPath: "\.yarn/releases/yarn-3\.1\.1\.cjs"
        remote:
        remote:               This will cause the buildpack to install yarn@3\.1\.1 but, when running Yarn commands, the vendored release
        remote:               at "\.yarn/releases/yarn-3\.1\.1\.cjs" will be executed instead\.
        remote:
        remote:               To ensure we install the version of Yarn you want, choose only one of the following actions:
        remote:               - Remove the "packageManager" field from package\.json
        remote:               - Remove the "yarnPath" configuration from \.yarnrc\.yml and delete the vendored release at "\.yarn/releases/yarn-3\.1\.1\.cjs"
        remote:               https://devcenter\.heroku\.com/articles/nodejs-support
        remote:
        remote:        No Node\.js version specified, resolving current LTS version\.\.\.
        remote:        Downloading and installing node .+\.\.\.
        remote:        Validating checksum
        remote:        Using default npm version: .+
        remote:        Downloading and installing yarn \(1\.22\.x\)
        remote:        Using yarn .+
      REGEX
      expect(successful_body(app).strip).to eq("Hello from yarn2-pnp-nonzero-install")

      run!('git commit --allow-empty -m "deploy again to test cache reuse"')
      app.push!

      expect(app.output).to include("Restoring cache")
      expect(app.output).to include("- yarn cache")
      expect(successful_body(app).strip).to eq("Hello from yarn2-pnp-nonzero-install")
    end
  end

  # Example uses the node-modules linker (e.g. node standard module resolution)
  # and pushes all dependencies in .yarn/cache. No packages should be downloaded
  # and buildcache is not used in this mode.
  it "node_modules zero install should deploy successfully and reuse the cache" do
    app = Hatchet::Runner.new("spec/fixtures/repos/yarn2-modules-zero-install")
    app.deploy do |app|
      expect(clean_output(app.output)).to match(Regexp.new(<<~'REGEX'))
        remote: -----> Installing binaries
        remote:        engines\.node \(package\.json\):   unspecified
        remote:        engines\.npm \(package\.json\):    unspecified \(use default\)
        remote:        engines\.yarn \(package\.json\):   unspecified \(use default\)
        remote:        packageManager \(package\.json\): yarn@3\.1\.1
        remote:
        remote:         !     Yarn release script may conflict with "packageManager"
        remote:
        remote:               The package\.json file indicates the target version of Yarn to install with:
        remote:               - "packageManager": "yarn@3\.1\.1"
        remote:
        remote:               But the \.yarnrc\.yml configuration indicates a vendored release of Yarn should be used with:
        remote:               - yarnPath: "\.yarn/releases/yarn-3\.1\.1\.cjs"
        remote:
        remote:               This will cause the buildpack to install yarn@3\.1\.1 but, when running Yarn commands, the vendored release
        remote:               at "\.yarn/releases/yarn-3\.1\.1\.cjs" will be executed instead\.
        remote:
        remote:               To ensure we install the version of Yarn you want, choose only one of the following actions:
        remote:               - Remove the "packageManager" field from package\.json
        remote:               - Remove the "yarnPath" configuration from \.yarnrc\.yml and delete the vendored release at "\.yarn/releases/yarn-3\.1\.1\.cjs"
        remote:               https://devcenter\.heroku\.com/articles/nodejs-support
        remote:
        remote:        No Node\.js version specified, resolving current LTS version\.\.\.
        remote:        Downloading and installing node .+\.\.\.
        remote:        Validating checksum
        remote:        Using default npm version: .+
        remote:        Downloading and installing yarn \(1\.22\.x\)
        remote:        Using yarn .+
      REGEX
      expect(successful_body(app).strip).to eq("Hello from yarn2-modules-zero-install")

      run!('git commit --allow-empty -m "deploy again to test cache reuse"')
      app.push!

      expect(app.output).to include("yarn cache is checked into source control and cannot be cached")
      expect(successful_body(app).strip).to eq("Hello from yarn2-modules-zero-install")
    end
  end

  # Example uses the node-modules linker (e.g. node standard module resolution)
  # and does not push dependencies in .yarn/cache. All packages will either be
  # restored from the buildcache or downloaded.
  it "node_modules nonzero install should deploy successfully and reuse the cache" do
    app = Hatchet::Runner.new("spec/fixtures/repos/yarn2-modules-nonzero-install")
    app.deploy do |app|
      expect(clean_output(app.output)).to match(Regexp.new(<<~'REGEX'))
        remote: -----> Installing binaries
        remote:        engines\.node \(package\.json\):   unspecified
        remote:        engines\.npm \(package\.json\):    unspecified \(use default\)
        remote:        engines\.yarn \(package\.json\):   unspecified \(use default\)
        remote:        packageManager \(package\.json\): yarn@3\.1\.1
        remote:
        remote:         !     Yarn release script may conflict with "packageManager"
        remote:
        remote:               The package\.json file indicates the target version of Yarn to install with:
        remote:               - "packageManager": "yarn@3\.1\.1"
        remote:
        remote:               But the \.yarnrc\.yml configuration indicates a vendored release of Yarn should be used with:
        remote:               - yarnPath: "\.yarn/releases/yarn-3\.1\.1\.cjs"
        remote:
        remote:               This will cause the buildpack to install yarn@3\.1\.1 but, when running Yarn commands, the vendored release
        remote:               at "\.yarn/releases/yarn-3\.1\.1\.cjs" will be executed instead\.
        remote:
        remote:               To ensure we install the version of Yarn you want, choose only one of the following actions:
        remote:               - Remove the "packageManager" field from package\.json
        remote:               - Remove the "yarnPath" configuration from \.yarnrc\.yml and delete the vendored release at "\.yarn/releases/yarn-3\.1\.1\.cjs"
        remote:               https://devcenter\.heroku\.com/articles/nodejs-support
        remote:
        remote:        No Node\.js version specified, resolving current LTS version\.\.\.
        remote:        Downloading and installing node .+\.\.\.
        remote:        Validating checksum
        remote:        Using default npm version: .+
        remote:        Downloading and installing yarn \(1\.22\.x\)
        remote:        Using yarn .+
      REGEX
      expect(successful_body(app).strip).to eq("Hello from yarn2-modules-nonzero-install")

      run!('git commit --allow-empty -m "deploy again to test cache reuse"')
      app.push!

      expect(app.output).to include("Restoring cache")
      expect(app.output).to include("- yarn cache")
      expect(successful_body(app).strip).to eq("Hello from yarn2-modules-nonzero-install")
    end
  end
end
