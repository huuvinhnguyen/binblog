module ApplicationHelper
    def meta_title
        content_for?(:meta_title) ? content_for(:meta_title) : "KhuônViên"
    end

    def meta_description
        content_for?(:meta_description) ? content_for(:meta_description) : "Giải pháp Thiết bị Thông minh cho Nông nghiệp công nghệ cao"
    end

    def meta_image
        content_for?(:meta_image) ? content_for(:meta_image) : asset_url("favicon.svg")
    end

    def meta_url
        request.original_url
    end
end
