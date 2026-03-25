-- Включаем расширение для векторов
CREATE EXTENSION IF NOT EXISTS vector;

-- Таблица книг
CREATE TABLE IF NOT EXISTS books (
  id          BIGSERIAL    PRIMARY KEY,
  file_name   TEXT         NOT NULL UNIQUE,
  title       TEXT,
  size_bytes  INTEGER      NOT NULL DEFAULT 0,
  chunk_count INTEGER      NOT NULL DEFAULT 0,
  uploaded_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Таблица фрагментов
CREATE TABLE IF NOT EXISTS chunks (
  id          BIGSERIAL    PRIMARY KEY,
  book_id     BIGINT       NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  book_name   TEXT         NOT NULL,
  chapter     TEXT         NOT NULL DEFAULT 'Начало',
  line_start  INTEGER      NOT NULL DEFAULT 0,
  line_end    INTEGER      NOT NULL DEFAULT 0,
  content     TEXT         NOT NULL,
  embedding   vector(1024),
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Индекс для быстрого векторного поиска
CREATE INDEX IF NOT EXISTS idx_chunks_embedding_hnsw
ON chunks USING hnsw (embedding vector_cosine_ops);

-- RPC-функция для поиска по эмбеддингу
CREATE OR REPLACE FUNCTION search_by_embedding(
  query_embedding vector(1024),
  match_threshold FLOAT DEFAULT 0.3,
  top_k           INTEGER DEFAULT 5,
  p_book_id       BIGINT DEFAULT NULL
)
RETURNS TABLE (
  id         BIGINT,
  book_name  TEXT,
  chapter    TEXT,
  line_start INTEGER,
  line_end   INTEGER,
  content    TEXT,
  similarity FLOAT
)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT c.id, c.book_name, c.chapter, c.line_start, c.line_end, c.content,
         1 - (c.embedding <=> query_embedding) AS similarity
  FROM chunks c
  WHERE c.embedding IS NOT NULL
    AND (p_book_id IS NULL OR c.book_id = p_book_id)
    AND (1 - (c.embedding <=> query_embedding)) >= match_threshold
  ORDER BY c.embedding <=> query_embedding
  LIMIT top_k;
$$;

-- Функция для создания/обновления книги
CREATE OR REPLACE FUNCTION public.get_or_create_book(
  p_file_name TEXT, p_title TEXT, p_size_bytes INTEGER, p_chunk_count INTEGER
)
RETURNS TABLE (id BIGINT)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  INSERT INTO public.books (file_name, title, size_bytes, chunk_count)
  VALUES (p_file_name, p_title, p_size_bytes, p_chunk_count)
  ON CONFLICT (file_name)
  DO UPDATE SET size_bytes = EXCLUDED.size_bytes, chunk_count = EXCLUDED.chunk_count
  RETURNING books.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_or_create_book TO anon, authenticated, service_role;
NOTIFY pgrst, 'reload schema';
