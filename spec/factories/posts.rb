FactoryBot.define do
  factory :post do
    title { "MyString" }
    content { "MyText" }
    slug { "MyString" }
    published { false }
  end
end
