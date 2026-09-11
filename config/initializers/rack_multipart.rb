# Fix Rack::Multipart::MultipartTotalPartLimitError
# Increase the limit for forms with many fields (default is 128)
# Rails Admin with nested JSON fields can generate hundreds of input fields
Rack::Utils.multipart_total_part_limit = 5000
