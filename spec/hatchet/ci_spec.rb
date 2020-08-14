require_relative '../spec_helper'

#Test CI deploys run tests and use the cache
describe "Heroku CI" do
  it "Uses the cache" do
    Hatchet::Runner.new("node-js-getting-started").run_ci do |test_run|
      # puts test_run.output
      # what is the behavior of this for node js
      # expect(test_run.output).to match("Fetching rake")
      puts test_run.class
      puts test_run.output
      puts test_run.methods
      test_run.run_again
      puts test_run.output
      expect(test_run.output).to match("Using rake")
      expect(test_run.output).to_not match("Fetching rake")
    end
  end
end
