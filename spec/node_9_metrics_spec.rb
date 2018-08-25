require_relative 'spec_helper'

branch = ENV['HATCHET_BUILDPACK_BRANCH'] || "master"

describe "Node Metrics for v9.x" do
  context "test metrics for Node v9.x app" do
    let(:app) {
      Hatchet::Runner.new(
        "spec/fixtures/repos/node-9-metrics",
        buildpacks: ["https://github.com/heroku/heroku-buildpack-nodejs.git##{branch}"],
        config: {
          "HEROKU_METRICS_URL" => "http://localhost:3000",
          "METRICS_INTERVAL_OVERRIDE" => "10000"
        }
      )
    }

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
