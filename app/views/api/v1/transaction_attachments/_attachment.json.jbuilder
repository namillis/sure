# frozen_string_literal: true

json.id attachment.id
json.filename attachment.filename.to_s
json.content_type attachment.content_type
json.byte_size attachment.byte_size
json.created_at attachment.created_at.iso8601
# Needs the same API credentials as any other call; there is no public link to the file.
json.url api_v1_attachment_url(attachment)
