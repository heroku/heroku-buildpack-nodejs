require_relative '../spec_helper'

describe "yarn2 examples" do
  # Example uses the pnp linker and pushes all dependencies in .yarn/cache.
  # No packages should be downloaded and buildcache is not used in this mode.
  it "pnp zero-install with should deploy successfully and not use the cache" do
    app = Hatchet::Runner.new("spec/fixtures/repos/yarn2-pnp-zero-install")
    app.deploy do |app|
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
      expect(successful_body(app).strip).to eq("Hello from yarn2-modules-nonzero-install")

      run!('git commit --allow-empty -m "deploy again to test cache reuse"')
      app.push!

      expect(app.output).to include("Restoring cache")
      expect(app.output).to include("- yarn cache")
      expect(successful_body(app).strip).to eq("Hello from yarn2-modules-nonzero-install")
    end
  end
end

