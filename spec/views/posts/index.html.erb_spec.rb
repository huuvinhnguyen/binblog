require 'rails_helper'

# RSpec.describe "posts/index", type: :view do
#   before(:each) do
#     assign(:posts, [
#       Post.create!(
#         title: "Title",
#         content: "MyText",
#         slug: "Slug",
#         published: false
#       ),
#       Post.create!(
#         title: "Title",
#         content: "MyText",
#         slug: "Slug",
#         published: false
#       )
#     ])
#   end

#   it "renders a list of posts" do
#     render
#     cell_selector = 'div>p'
#     assert_select cell_selector, text: Regexp.new("Title".to_s), count: 2
#     assert_select cell_selector, text: Regexp.new("MyText".to_s), count: 2
#     assert_select cell_selector, text: Regexp.new("Slug".to_s), count: 2
#     assert_select cell_selector, text: Regexp.new(false.to_s), count: 2
#   end
# end
