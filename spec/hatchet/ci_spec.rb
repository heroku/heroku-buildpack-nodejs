require_relative '../spec_helper'

#Test CI deploys run tests and use the cache
describe "Heroku CI" do
  it "Uses the cache" do
    Hatchet::Runner.new("node-js-getting-started").run_ci do |test_run|
      # puts test_run.output
      # what is the behavior of this for node js
      # expect(test_run.output).to match("Fetching rake")
      expect(test_run.output).to_not include("Restoring cache")
      test_run.run_again
      expect(test_run.output).to include("Restoring cache")
    end
  end
end
