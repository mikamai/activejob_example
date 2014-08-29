## Rails 4.2 new gems: activejob and globalid

A few days ago the new rails 4.2 beta release was [announced](http://weblog.rubyonrails.org/releases/) and the usual bag of goodies is going to make our life as developers easier and more interesting.

The most relevant new feature is the **Active Job** framework and its integration with ActionMailer: rails has now its own queue interface and you can swap the queuing gem (resque, delayed job, sidekiq...) without changing your application code.
You can even send email asyncronously with the new `deliver_later` method, but if you want sync delivery you should use instead `deliver_now` because the old `deliver method` is now deprecated.

If you don't add any queue gem to the Gemfile then the default rails system will be used, which means that everything will be sent immediately (no async functionality).

The new feature depends on a couple of new gems: [active job](https://github.com/rails/rails/tree/master/activejob) and [global id](https://github.com/rails/globalid). Active Job usage is well documented in the [new official guide](http://edgeguides.rubyonrails.org/active_job_basics.html), so I will focus most of this article on Global Id.

If you want to follow along you can download a demo app from [this repository](https://github.com/mikamai/activejob_example), bundle the gems and start the server with `rails s`. The example is just a rails 4.2 app with a regular ActiveRecord Friend scaffold and a NameCapitalizerJob job class.

How do the new gems interact exactly? Let's enqueue a new job for the NameCapitalizerJob worker, which is located in the example application:
```ruby
NameCapitalizerJob.enqueue Friend.first
=> #<NameCapitalizerJob:0x007fb44acaff48 ...>
```

If you used rails queuing systems in the past you already know that it was necessary to pass your ActiveRecord objects to the worker in the form of their id and manually reload the record at job execution. This is no more required, so in the example above we're simply passing the record itself, while in the job code the reload is automatic:

```ruby
NameCapitalizerJob < ActiveJob::Base
  def perform(friend)
    name = friend.name.capitalize
    friend.update_attribute :name, name
  end
end
```

You can see the job has been correctly enqueued:

```ruby
Delayed::Job.count
 => 1
```

with the following params:

```ruby
YAML.load(Delayed::Job.first.handler).args
 => [NameCapitalizerJob, "4a33725b-35cf-4940-b1ca-d6fad84d410f", "gid://activejob-example/Friend/1"]
```

These params represent: the job class name, the job id, and the global id string representation for the `Friend.first` record.

The format of the global id string is `gid://AppName/ModelClassName/record_id`.

Given a gobal id, the worker will load the referenced record transparently. This is achieved by mixing in a module from the global id gem into ActiveRecord::Base:

```ruby
puts ActiveRecord::Base.ancestors
...
GlobalID::Identification
...
```

The `GlobalID::Identification` module defines only a couple of methods: `#global_id`, `#signed_global_id` and their aliases `#gid` and `#sgid`, where the first is the record's globalid object, the second is the record's signed(encrypted) version of the same object:

```ruby
gid = Friend.first.gid
 => #<GlobalID:0x007fa9add041f8 ...>
gid.app
 => "activejob-example"
gid.model_name
 => "Friend"
gid.model_class
 => Friend(id: integer, name: string, email: string...)
gid.model_id
 => "1"
gid.to_s
 => "gid://activejob-example/Friend/1"

sgid = Friend.first.sgid
 => #<SignedGlobalID:0x007fa9add15e58 ...>
sgid.to_s
 => "BAh7CEkiCGdpZAY6BkVUSSIlZ2lkOi8vYWN0aXZl..."
```

The most important thing here is the string representation of the gid, as it contains enough information to retrieve its original record:

```ruby
GlobalID::Locator.locate "gid://activejob-example/Friend/1"
 => #<Friend id: 1, name: "John smith" ...>
```

The actual source code used for locating records is rather simple and self explanatory:

```ruby
class ActiveRecordFinder
  def locate(gid)
    gid.model_class.find gid.model_id
  end
end
```

Regarding the signed object, we can inspect the original data hidden into its string representation using the following code:

```ruby
SignedGlobalID.verifier.verify sgid.to_s
 => {"gid"=>"gid://activejob-example/Friend/1", "purpose"=>"default", "expires_at"=>Mon, 29 Sep 2014 08:25:31 UTC +00:00}
```

That's how the global id gem works inside rails. By the way, it's rather easy to use it with your own classes. Let's see how to to it.

First you need to install the gem: `gem install globalid`, then start a new irb session and require it with  `require 'globalid'`.

The gem requires an `app` namespace in order to generate ids, so we need to set it manually:

```ruby
GlobalID.app = 'TestApp'`
```

Now let's build a PORO class that defines globalid required methods (`::find ` and `id`) and includes the `GlobalID::Identification` module:

```ruby
class Item
  include GlobalID::Identification

  @all = []
  def self.all; @all end

  def self.find(id)
    all.detect {|item| item.id.to_s == id.to_s }
  end

  def initialize
    self.class.all << self
  end

  def id
    object_id
  end
end
```

As you might guess, the `::find` method retrieves an item from its id code, while the `#id` method is simply an identifier. It works like this:

```ruby
item = Item.new
 => #<Item:0x007fdb4b05da10>
id = item.id
 => 70289916620040
Item.find(id)
 => #<Item:0x007fdb4b05da10>
```

Time to get the item global id:

```ruby
gid = item.gid
 => #<GlobalID:0x007fdb4b026358 ...>
gid.app
 => "TestApp"
gid.model_name
 => "Item"
gid.model_id
 => "70289916620040"
gid_uri = gid.to_s
 => "gid://TestApp/Item/70289916620040"
```
We can now retrieve the original Item object from the gid_uri:
```ruby
found = GlobalID.locate gid_uri
 => #<Item:0x007fdb4b05da10>
found == item
 => true
```