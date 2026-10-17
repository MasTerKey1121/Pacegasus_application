CREATE TABLE IF NOT EXISTS club_images (
  id UUID PRIMARY KEY,
  content_type VARCHAR(32) NOT NULL CHECK (content_type IN ('image/png', 'image/jpeg', 'image/webp')),
  image_data BYTEA NOT NULL CHECK (octet_length(image_data) <= 2097152),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
