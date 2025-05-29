json.extract! post, :id, :title, :content, :slug, :published, :created_at, :updated_at
json.url post_url(post, format: :json)
