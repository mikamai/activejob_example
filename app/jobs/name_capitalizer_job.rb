class NameCapitalizerJob < ActiveJob::Base
  queue_as :default

  def perform(friend)
    name = friend.name.capitalize
    friend.update_attribute :name, name
  end
end
