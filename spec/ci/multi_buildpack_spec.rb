require_relative "../spec_helper"

describe "Multi-buildpack pnpm" do
  it "exports pnpm store-dir for subsequent buildpacks" do
    buildpacks = [
      :default,
      "heroku/ruby"
    ]
    Hatchet::Runner.new("spec/fixtures/repos/multi-buildpack-pnpm-rails", buildpacks: buildpacks, stack: "heroku-24").deploy do |app|
      output = clean_output(app.output)
      expect(output).to include("Build succeeded!")
      expect(output).not_to include("ERR_PNPM_ABORTED_REMOVE_MODULES_DIR_NO_TTY")
      expect(output).to match(/npm_config_store_dir=/)
    end
  end
end
