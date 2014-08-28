json.array!(@friends) do |friend|
  json.extract! friend, :id, :name, :email
  json.url friend_url(friend, format: :json)
end
