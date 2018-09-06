require_relative '../spec_helper'

describe "Node metrics plugin should not fail other Node binaries" do
  context "an app that runs the Heroku CLI with metrics" do
    let(:app) {
      Hatchet::Runner.new(
        "spec/fixtures/repos/node-metrics-conflict",
        buildpacks: [
          Hatchet::App.default_buildpack,
          "https://github.com/heroku/heroku-buildpack-cli"
        ],
        config: {
          "HEROKU_METRICS_URL" => "http://localhost:3000"
        }
      )
    }

    it "should not run within the heroku cli" do
      app.deploy do |app|
        data = successful_body(app)
        expect(data).to include("not logged in")
        expect(data).not_to include("was compiled against a different Node.js version")
      end
    end
  end
end
