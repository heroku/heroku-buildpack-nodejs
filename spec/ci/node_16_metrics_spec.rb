require_relative '../spec_helper'

describe "Node Metrics for v16.x" do
  context "test metrics for Node v16x app" do
    let(:app) {
      Hatchet::Runner.new(
        "spec/fixtures/repos/node-16-metrics",
        config: {
          "HEROKU_METRICS_URL" => "http://localhost:3000",
          "METRICS_INTERVAL_OVERRIDE" => "10000"
        }
      )
    }

    it "should deploy" do
      app.deploy do |app|
        data = successful_json_body(app)
        expect(data["gauges"]["node.eventloop.delay.ms.max"]).to be >= 2000
        expect(data["counters"]["node.gc.collections"]).to be >= 0
        expect(data["counters"]["node.gc.young.collections"]).to be >= 0
        expect(data["counters"]["node.gc.old.collections"]).to be >= 0
      end
    end
  end
end
