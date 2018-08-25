require_relative 'spec_helper'

branch = ENV['HATCHET_BUILDPACK_BRANCH'] || "master"

describe "Hello World for Node v8.x" do
  context "a single-process Node v8.x app" do
    let(:app) {
      Hatchet::Runner.new(
        "spec/fixtures/repos/node-8",
        buildpacks: ["https://github.com/heroku/heroku-buildpack-nodejs.git##{branch}"]
      )
    }

    it "should deploy successfully" do
      app.deploy do |app|
        expect(app.output).to include("-----> Build succeeded!")
        expect(successful_body(app).strip).to eq("Hello, world!")
      end
    end

  end
end
