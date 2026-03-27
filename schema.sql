-- 1. Включаем расширение для векторов 
CREATE EXTENSION IF NOT EXISTS vector;


CREATE TABLE IF NOT EXISTS books (
  id BIGSERIAL PRIMARY KEY,
  title TEXT UNIQUE, 
  uploaded_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==========================================
-- 3. ТАБЛИЦА CHUNKS (Адаптация под LangChain)

DROP TABLE IF EXISTS chunks CASCADE;

-- Создаем новую по стандарту n8n LangChain
CREATE TABLE chunks (
  id BIGSERIAL PRIMARY KEY,
  content TEXT NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb, -- Все главы и названия будут храниться здесь
  embedding vector(1024) -- размерность mxbai-embed-large-v1
);

-- Индекс для супербыстрого поиска
CREATE INDEX ON chunks USING hnsw (embedding vector_cosine_ops);

-- ==========================================
-- 4. ПОЛИТИКИ ДОСТУПА (RLS)


ALTER TABLE books ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public access books" ON books;
CREATE POLICY "public access books" ON books FOR ALL USING (true);


-- ==========================================
-- 5. ФУНКЦИЯ ПОИСКА ДЛЯ AI AGENT (match_documents)

CREATE OR REPLACE FUNCTION match_documents (
  query_embedding vector(1024), 
  match_count int DEFAULT 10,
  filter jsonb DEFAULT '{}'
) RETURNS TABLE (
  id bigint,
  content text,
  metadata jsonb,
  similarity float
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    c.id,
    c.content,
    c.metadata,
    1 - (c.embedding <=> query_embedding) AS similarity
  FROM chunks c
  WHERE c.metadata @> filter
  ORDER BY c.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;
