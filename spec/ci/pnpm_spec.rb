require_relative '../spec_helper'

describe "pnpm support" do
  it "should successfully deploy a pnpm workspace with pruned devDependencies" do
    app = Hatchet::Runner.new("spec/fixtures/repos/pnpm-workspace")
    app.deploy do |app|
      expect(app.output).to include("Using pnpm")
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
