require_relative 'spec_helper'

branch = ENV['HATCHET_BUILDPACK_BRANCH'] || "master"
versions = get_test_versions()

versions.select{ |version| version_supports_metrics(version) }.each do |version|
  describe "Node Metrics for v#{version}" do
    before(:each) do
      set_node_version(app.directory, node_version)
      app.setup!
      app.set_config({
        "HEROKU_METRICS_URL" => "http://localhost:3000",
        "METRICS_INTERVAL_OVERRIDE" => "10000"
      })
    end

    context "test metrics for Node v#{version} app" do
      let(:app) {
        Hatchet::Runner.new(
          "node-metrics-test-app",
          buildpacks: ["https://github.com/heroku/heroku-buildpack-nodejs.git##{branch}"]
        )
      }

      let(:node_version) { version }
      it "should deploy" do
        app.deploy do |app|
          expect(app.output).to include("-----> Build succeeded!")
          data = successful_json_body(app)
          expect(data["gauges"]["node.eventloop.delay.ms.max"]).to be >= 2000
          expect(data["counters"]["node.gc.collections"]).to be >= 0
          expect(data["counters"]["node.gc.young.collections"]).to be >= 0
          expect(data["counters"]["node.gc.old.collections"]).to be >= 0
        end
      end
    end
  end
end
