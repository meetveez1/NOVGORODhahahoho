# 📚 Умный поиск по книгам
# Сейчас ведутся экстренные работы по восстановлению работоспособности функционала, это займет 2-3 дня максимум

[Телеграм-бот](@MATVEYKOLESO_bot)для семантического поиска по текстам книг и ответов на вопросы по их содержанию. Реализован на базе RAG-подхода: текст книги разбивается на фрагменты, каждый фрагмент превращается в векторное представление, а при запросе система находит наиболее близкие по смыслу фрагменты и формирует ответ.

---

## 🛠 Стек технологий

| Компонент | Технология |
|---|---|
| Оркестрация | [n8n](https://n8n.io/) (no-code/low-code автоматизация) |
| Интерфейс | Telegram Bot API |
| Векторная БД | [Supabase](https://supabase.com/) + расширение `pgvector` |
| Эмбеддинги | [mxbai-embed-large-v1](https://huggingface.co/mixedbread-ai/mxbai-embed-large-v1) (HuggingFace Inference API) |
| LLM для ответов | [OpenRouter](https://openrouter.ai) (модель по выбору) [у нас](https://openrouter.ai/nvidia/nemotron-3-super-120b-a12b:free/uptime)  |

---

## 🚀 Как запустить сервис

### 1. Требования

- Аккаунт [n8n](https://n8n.io/) (cloud или self-hosted)
- Аккаунт [Supabase](https://supabase.com/)
- Аккаунт [HuggingFace](https://huggingface.co/) (бесплатный токен)
- Аккаунт [OpenRouter](https://openrouter.ai/)
- Telegram-бот (создать через [@BotFather](https://t.me/BotFather))

### 2. Подготовка базы данных

В Supabase откройте SQL Editor и выполните следующий скрипт:

```sql
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
```

### 3. Импорт воркфлоу в n8n

1. Скачайте файл `workflow.json` из корня репозитория.
2. В n8n: **Workflows → Import from file** → выберите `workflow.json`.
3. Настройте credentials (см. ниже).
4. Активируйте воркфлоу.

### 4. Настройка credentials в n8n

| Название | Тип | Что указать |
|---|---|---|
| `Telegram account` | Telegram API | Token от BotFather |
| `Header Auth account` | HTTP Header Auth | `apikey: <ваш Supabase anon/service key>` |
| `Bearer Auth account` | HTTP Bearer Auth | HuggingFace API token |
| `Supabase account` | Supabase | URL и Service Role Key |
| `API LLM` | OpenRouter API | API key OpenRouter |

---

## 📖 Как загрузить книгу

1. Откройте бота в Telegram.
2. Напишите `/upload` или просто **отправьте `.txt` файл** прямо в чат.
3. Бот запросит подтверждение и начнёт обработку: нарежет текст на фрагменты (~1200 символов с перекрытием), получит эмбеддинги для каждого фрагмента и сохранит в базу.
4. После завершения бот сообщит количество загруженных фрагментов.

> ⚠️ Книги должны быть в формате `.txt` в кодировке UTF-8. Для конвертации из других форматов можно использовать [fb2converter](https://github.com/rupor-github/fb2c) или аналоги.

---

## 💬 Команды бота

| Команда | Описание |
|---|---|
| `/start` | Приветствие и список команд |
| `/books` | Список загруженных книг |
| `/search <запрос>` | Найти фрагменты текста по запросу |
| `/ask <вопрос>` | Задать вопрос по содержанию книг |

---

## 🧪 Примеры работы пока в процессе создания - резко возникли проблемы с нейросетью и embed моделью


## 📁 Структура репозитория

```
.
├── workflow.json       # Воркфлоу n8n (импортировать в интерфейсе)
├── schema.sql          # SQL-скрипт для создания таблиц и функций
└── README.md
```

---

## ⚙️ Как устроена система

```
Пользователь (Telegram)
       ↓
  Роутер команд
  ├── /upload → нарезка на чанки → эмбеддинги → Supabase
  ├── /search → эмбеддинг запроса → векторный поиск → форматирование
  ├── /ask    → эмбеддинг запроса → векторный поиск → LLM → ответ
  └── /books  → список из Supabase
```

Поиск работает через косинусное сходство векторов: запрос пользователя и все фрагменты книг переводятся в векторы одной моделью (`mxbai-embed-large-v1`), после чего система выбирает наиболее близкие фрагменты.
