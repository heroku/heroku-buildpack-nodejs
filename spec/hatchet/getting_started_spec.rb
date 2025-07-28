require_relative '../spec_helper'

#Test deploying the getting started guide works
describe "Heroku node getting started" do
  it "clears runtime cache" do
    Hatchet::Runner.new("nodejs-getting-started").deploy do |app|
      #Deploy works
    end
  end
end
