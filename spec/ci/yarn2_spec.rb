require_relative '../spec_helper'

describe "yarn2 examples" do
  it "pnp zero-install with should deploy successfully and not use the cache" do
    app = Hatchet::Runner.new("spec/fixtures/repos/yarn2-pnp-zero-install")
    app.deploy do |app|
      expect(successful_body(app).strip).to eq("Hello from yarn-pnp-zero-install")

      run!('git commit --allow-empty -m "deploy again to test cache reuse"')
      app.push!

      expect(app.output).to include("yarn cache is checked into source control and cannot be cached")
      expect(successful_body(app).strip).to eq("Hello from yarn-pnp-zero-install")
    end
  end

  it "pnp nonzero-install should deploy successfully and reuse the cache" do
    app = Hatchet::Runner.new("spec/fixtures/repos/yarn2-pnp-nonzero-install")
    app.deploy do |app|
      expect(successful_body(app).strip).to eq("Hello from yarn-pnp-nonzero-install")

      run!('git commit --allow-empty -m "deploy again to test cache reuse"')
      app.push!

      expect(app.output).to include("Restoring cache")
      expect(app.output).to include("- yarn cache")
      expect(successful_body(app).strip).to eq("Hello from yarn-pnp-nonzero-install")
    end
  end
end

