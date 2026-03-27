# 📚 Умный поиск по книгам

Телеграм-бот @Books_SearchAndUpload_bot для семантического поиска по текстам книг и ответов на вопросы по их содержанию. Реализован на базе RAG-подхода: текст книги разбивается на фрагменты, каждый фрагмент превращается в векторное представление, а при запросе система находит наиболее близкие по смыслу фрагменты и формирует ответ.

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
| `API LLM` | OpenRouter API | API ключ из личного кабинета OpenRouter |

---

## 📖 Как загрузить книгу

1. Откройте бота в Telegram.
2. Напишите `/upload`.
3. Бот начнёт обработку: нарежет текст на фрагменты, получит эмбеддинги для каждого фрагмента и сохранит в базу.
4. После завершения бот сообщит количество загруженных фрагментов.

> ⚠️ Книги должны быть в формате `.txt` в кодировке UTF-8. Для конвертации из других форматов можно использовать [fb2converter](https://github.com/rupor-github/fb2c) или аналоги.

---

## 💬 Команды бота

| Команда | Описание |
|---|---|
| `/start` | Приветствие и список команд |
| `/list_books` | Список загруженных книг |
| `/search` | Задать вопрос по содержанию книги с помощью формы |
| `/upload` | Загрузить книгу |

---

## 🧪 Пример работы
<img width="963" height="886" alt="image" src="https://github.com/user-attachments/assets/fd69ff59-1891-4e23-a32b-2e01f4229360" />

#Книга — Тарас Бульба


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
  ├── /start → Отправка справки
  ├── /upload → нарезка на чанки → эмбеддинги → Supabase
  ├── /search → эмбеддинг запроса → векторный поиск → форматирование
  └── /list_books  → список из Supabase
```

Поиск работает через косинусное сходство векторов: запрос пользователя и все фрагменты книг переводятся в векторы одной моделью (`mxbai-embed-large-v1`), после чего система выбирает наиболее близкие фрагменты.
