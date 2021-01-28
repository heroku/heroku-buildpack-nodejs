require_relative '../spec_helper'

versions = get_test_versions

versions.select { |version| version_supports_metrics(version) }.each do |version|
  describe "Node Metrics for v#{version}" do
    context "test metrics for Node v#{version} app" do
      let(:app) {
        Hatchet::Runner.new(
          "spec/fixtures/repos/node-14-metrics",
          before_deploy: -> { set_node_version(version) },
          config: {
            "HEROKU_METRICS_URL" => "http://localhost:3000",
            "METRICS_INTERVAL_OVERRIDE" => "10000"
          }
        )
      }

      it "should deploy" do
        app.deploy do |app|
          expect(app.output).to include("Downloading and installing node #{version}...")
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
