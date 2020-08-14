require_relative '../spec_helper'

#Test that all paths set by the buildpack are absolute instead of relative
describe "Rails 5.1" do
  it "works with webpacker + yarn (js friends)" do
    buildpacks = [
      ENV["HATCHET_BUILDPACK_BASE"],
      "https://github.com/sharpstone/force_absolute_paths_buildpack"
    ]
    Hatchet::Runner.new("node-js-getting-started", buildpacks: buildpacks).deploy do |app|
      #deploy works
    end
  end
end
