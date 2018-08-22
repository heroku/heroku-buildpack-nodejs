require_relative 'spec_helper'

branch = ENV['HATCHET_BUILDPACK_BRANCH'] || "master"
versions = get_test_versions()

versions.each do |version|
  describe "Hello World for Node v#{version}" do
    before(:each) do
      set_node_version(app.directory, node_version)
      app.setup!
    end

    context "a single-process Node v#{version} app" do
      let(:app) {
        Hatchet::Runner.new(
          "node-metrics-multi-process",
          buildpacks: ["https://github.com/heroku/heroku-buildpack-nodejs.git##{branch}"]
        )
      }
      let(:node_version) { version }

      it "should deploy successfully" do
        app.deploy do |app|
          expect(app.output).to include("-----> Build succeeded!")
          expect(successful_body(app).strip).to eq("Hello, world!")
        end
      end

    end
  end
end

