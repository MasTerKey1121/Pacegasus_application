CREATE TABLE IF NOT EXISTS avatar_images (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  content_type VARCHAR(32) NOT NULL CHECK (content_type IN ('image/png', 'image/jpeg', 'image/webp')),
  image_data BYTEA NOT NULL CHECK (octet_length(image_data) <= 5242880),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
