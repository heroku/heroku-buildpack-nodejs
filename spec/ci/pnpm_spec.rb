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
        remote:        Using pnpm .+
      REGEX
      expect(app.output).to include("Running 'pnpm install' with pnpm-lock.yaml")
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
      expect(app.output).to include("Pruning devDependencies")
      expect(app.output).to include("devDependencies: skipped because NODE_ENV is set to production")
      expect(successful_body(app).strip).to eq("Hello from pnpm workspace")
    end
  end
end
