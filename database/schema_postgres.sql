-- =============================================================================
-- DaPlayer - Script de Criação das Tabelas para PostgreSQL (Neon.tech)
-- Banco: daplay
-- =============================================================================

-- 1. Tabela de Usuários
CREATE TABLE IF NOT EXISTS users (
  id VARCHAR(100) PRIMARY KEY,
  name VARCHAR(120) NOT NULL,
  email VARCHAR(180) UNIQUE NOT NULL,
  email_hash VARCHAR(128) UNIQUE NOT NULL,
  password_hash VARCHAR(255),
  salt VARCHAR(128),
  google_id VARCHAR(120),
  avatar_url TEXT,
  auth_provider VARCHAR(30) NOT NULL DEFAULT 'email',
  youtube_token TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Tabela de Assinaturas (Free, Pro, Premium)
CREATE TABLE IF NOT EXISTS subscriptions (
  id BIGSERIAL PRIMARY KEY,
  user_id VARCHAR(100) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plan VARCHAR(30) NOT NULL DEFAULT 'free',
  is_active BOOLEAN NOT NULL DEFAULT FALSE,
  max_playlists INT NOT NULL DEFAULT 5, -- -1 = ilimitado
  gateway_subscription_id VARCHAR(120),
  expires_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_subscription_user UNIQUE (user_id)
);

-- 3. Tabela de Coletâneas (Playlists)
CREATE TABLE IF NOT EXISTS playlists (
  id VARCHAR(100) PRIMARY KEY,
  user_id VARCHAR(100) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(150) NOT NULL,
  description TEXT DEFAULT '',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. Tabela de Músicas de cada Coletânea
CREATE TABLE IF NOT EXISTS playlist_tracks (
  id BIGSERIAL PRIMARY KEY,
  playlist_id VARCHAR(100) NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
  video_id VARCHAR(32) NOT NULL,
  title VARCHAR(255) NOT NULL,
  artist VARCHAR(180) NOT NULL,
  thumbnail_url TEXT NOT NULL,
  duration_seconds INT NOT NULL DEFAULT 0,
  position INT NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_playlists_user_id ON playlists(user_id);
CREATE INDEX IF NOT EXISTS idx_playlist_tracks_playlist_pos ON playlist_tracks(playlist_id, position);
