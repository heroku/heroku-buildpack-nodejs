require_relative '../spec_helper'

versions = get_test_versions

versions.each do |version|
  describe "Hello World for Node v#{version}" do
    context "a single-process Node v#{version} app" do
      let(:app) {
        Hatchet::Runner.new(
          "spec/fixtures/repos/node-14",
          before_deploy: -> { set_node_version(version) }
        )
      }

      it "should deploy successfully" do
        app.deploy do |app|
          expect(app.output).to include("Downloading and installing node #{version}...")
          expect(successful_body(app).strip).to eq("Hello, world!")
        end
      end
    end
  end
end
