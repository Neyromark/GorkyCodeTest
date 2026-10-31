# GorkyCodeTest — умный календарь во ВКонтакте

> Ассистент-календарь для личных сообщений ВК: пишешь или наговариваешь сообщение
> («завтра в 15:00 встреча с Ольгой»), бот понимает неготовку через GigaChat, сохраняет
> задачу или встречу в PostgreSQL и, если нужно, напоминает — в назначенное время сервис
> уведомлений присылает сообщение прямо в ВК.

Проект собран из четырёх независимых сервисов (git-подмодулей), которые запускаются
вместе одной командой через Docker Compose.

<p align="center">
  <img src="https://img.shields.io/badge/Python-3.12%2B-3776AB?logo=python&logoColor=white" alt="Python">
  <img src="https://img.shields.io/badge/FastAPI-009688?logo=fastapi&logoColor=white" alt="FastAPI">
  <img src="https://img.shields.io/badge/PostgreSQL-17-4169E1?logo=postgresql&logoColor=white" alt="PostgreSQL">
  <img src="https://img.shields.io/badge/GigaChat-LLM-1501B6?logo=hcn&logoColor=white" alt="GigaChat">
  <img src="https://img.shields.io/badge/docker-Docker%20Compose-2496ED?logo=docker&logoColor=white" alt="Docker Compose">
</p>

<p align="center">
  <a href="#архитектура">Архитектура</a> ·
  <a href="#состав">Состав</a> ·
  <a href="#быстрый-старт">Быстрый старт</a> ·
  <a href="#api">API</a> ·
  <a href="#модель-данных">Модель данных</a> ·
  <a href="#разработка-без-docker">Без Docker</a> ·
  <a href="#тесты">Тесты</a> ·
  <a href="#деплой">Деплой</a>
</p>

---

## О чём проект

- **ВК-бот** слушает личные сообщения: текст, голосовые, фразы вроде «завтра в 15:00».
- **Backend** понимает намерение через LLM, держит диалог, кладёт задачу в БД и ставит
  напоминание, если время указано или уточнил его.
- **Notifications** хранит запланированные уведомления и отправляет их боту в нужный момент.
- **PostgreSQL + pgvector** хранит задачи и позволяет семантический поиск по истории.

Результат ноль лишнему: одна встреча с ботом → задача в БД → напоминание в нужный час.

---

<a name="архитектура"></a>
## Архитектура

```text
             ВК (Long Poll)
                   │  текст / голосовое
                   ▼
        ┌──────────────────────┐
        │        VK-Bot        │  :80  (FastAPI + longpoll в одном процессе)
        └──────┬────────┬──────┘
               │        ▲
 POST /api/v1/ │        │ POST /api/v1/send-message
  get-message  │        │ (ответ пользователю и напоминания)
               ▼        │
        ┌──────────────────────┐        ┌───────────────────────┐
        │       Backend        │───────▶│     Notifications     │
        │ автомат + LLM + БД   │ :8000  │  APScheduler + jobs   │ :8080
        └──────┬────────┬──────┘        └───────────┬───────────┘
               │        │                           │
      SQLAlchemy│       │ GigaChat API              │ APScheduler
               ▼        ▼                           ▼
        ┌──────────────────────┐            (та же PostgreSQL)
        │  PostgreSQL+pgvector │◀───────────┘
        └──────────────────────┘
```

Два независимых потока:

1. **Сообщение пользователя.** Бот пересылает текст в `Backend` (`POST /api/v1/get-message`).
   Бэкенд определяет намерение (`create_task`, `list_events`, `search_history`), при создании
   задачи уточняет время напоминания, сохраняет запись и при необходимости вызывает
   `Notifications`. Готовый ответ бэкенд сам отправляет боту через
   `POST /api/v1/send-message`.
2. **Напоминание.** `Notifications` держит задания в PostgreSQL и по наступлении `date_notify`
   отправляет сообщение боту, а тот — пользователю.

Если нужно погуглить или обсудить интеграцию — [беседа во ВКонтакте](https://vk.ru/im/convo/-242449509?entrypoint=community_page&tab=all).

---

<a name="состав"></a>
## Состав

| Модуль | Стек | Порт на хосте | Ответственность |
| --- | --- | --- | --- |
| [`VK-Bot`](VK-Bot/README.md) | Python 3.12, vkbottle, FastAPI, Vosk | `80` | Long Poll ВК, приём текста и голосовых, HTTP-эндпоинт отправки сообщений |
| [`Backend`](Backend/README.md) | Python 3.12, FastAPI, SQLAlchemy 2, GigaChat, sentence-transformers | `8000` | Понимание сообщений (LLM), автомат диалога, задачи в БД, постановка напоминаний |
| [`Notifications`](Notifications/README.md) | Python 3.13, FastAPI, APScheduler | `${APP_PORT:-8000}` → `8080` в контейнере | Хранилище запланированных напоминаний и их доставка в бота |
| [`Database`](Database/README.md) | PostgreSQL 17 + pgvector | `${POSTGRES_PORT:-5432}` | Схема `user`, `tasks`, `done_tasks`, векторный поиск по заголовкам |

### Что делает каждый сервис

- **`VK-Bot`** — вход в систему: Long Poll сообщества, приём текстов и голосовых сообщений
  (Vosk → текст), HTTP-эндпоинт `send-message`, которым бэкенд отправляет ответы и
  напоминания.
- **`Backend`** — голова проекта: автомат диалога (стейты `IDLE` / `CLARIFY_DATE_NOTIFY`),
  вызов GigaChat для понимания сообщения, сохранение задач, семантический поиск по
  истории через `paraphrase-multilingual-mpnet-base-v2`.
- **`Notifications`** — тихий планировщик: APScheduler, хранилище запланированных job,
  дедупликация по содержимому запроса (`job_id`), форматирование сообщения по Москве.
- **`Database`** — PostgreSQL 17 с расширением `pgvector`: схема пользователей, задач,
  обработанных запросов и векторный индекс для поиска.

---

<a name="быстрый-старт"></a>
## Быстрый старт

Нужны Docker с плагином Compose и доступ в интернет: при сборке бэкенда скачивается
модель эмбеддингов, а при первом запуске бота — модель Vosk.

```bash
git clone --recurse-submodules https://github.com/Neyromark/GorkyCodeTest.git
cd GorkyCodeTest
```

### 1. Файлы окружения

Секреты живут в `.env` каждого модуля и не попадают в репозиторий.

```bash
cp Database/.env.example       Database/.env
cp Notifications/.env.example  Notifications/.env
cp VK-Bot/.env.example         VK-Bot/.env
cp Backend/.env.example        Backend/.env
```

В примерах уже прописаны адреса сервисов в сети `app-network` (`postgres`, `backend`,
`vkbottle_bot`, `notifications`) и свободные порты, поэтому дозаполнить нужно только
секреты:

| Модуль | Переменная | Значение |
| --- | --- | --- |
| `Database` | `POSTGRES_PASSWORD` | Пароль БД (обязателен, иначе compose не стартует) |
| `Database` | `POSTGRES_USER`, `POSTGRES_DB` | По умолчанию `postgres` / `tasks_db` |
| `Notifications` | `POSTGRES_PASSWORD` | Тот же пароль, что и в `Database` |
| `Notifications` | `APP_PORT` | Порт сервиса на хосте; в примере уже `8080` (8000 занят `Backend`) |
| `VK-Bot` | `VK_TOKEN` | Токен сообщества ВК (Long Poll + сообщения) |
| `VK-Bot` | `HOST`, `PORT` | Адрес бэкенда: в compose это `backend` и `8000` |
| `Backend` | `CREDENTIAL` | Authorization key GigaChat (`GIGACHAT_API_PERS`) |
| `Backend` | `DATABASE_URL` | `postgresql+psycopg://postgres:<пароль>@postgres:5432/tasks_db` — хост `postgres`, пароль как в `Database/.env` |
| `Backend` | `VK_BOT_URL`, `NOTIFICATIONS_URL` | По умолчанию `http://vkbottle_bot` и `http://notifications:8080` — менять не нужно |

> Порт `8000` публикуют и `Backend`, и `Notifications` (у последнего по умолчанию).
> В `Notifications/.env` уже стоит `APP_PORT=8080` — менять ничего не нужно.

### 2. Запуск

```bash
# Сеть объявлена как external, поэтому её нужно создать один раз
docker network create app-network 2>/dev/null || true
docker compose up -d --build
docker compose ps
docker compose logs -f backend
```

Корневой [docker-compose.yml](docker-compose.yml) подключает compose-файлы всех четырёх
модулей (`include`), объявляет общую сеть `app-network` и поднимает сервисы
`postgres`, `backend`, `vkbottle_bot`, `notifications`.

### 3. Проверка

```bash
# Бэкенд отвечает (нужён X-Request-ID — UUID4)
curl -s -X POST http://localhost:8000/api/v1/get-message \
  -H 'Content-Type: application/json' \
  -H "X-Request-ID: $(python -c 'import uuid; print(uuid.uuid4())')" \
  -d '{"user_id": 1, "message": "Завтра в 15:00 встреча с Ольгой"}'

# Сервис уведомлений: интерактивная документация
# http://localhost:<APP_PORT>/docs   (APP_PORT из Notifications/.env, по умолчанию 8000)
```

Затем напишите сообщество в личные сообщения: «начать», обычный текст или голосовое.

---

<a name="api"></a>
## API

Вызовы `Backend` и `VK-Bot` идемпотентны по заголовку `X-Request-ID` (UUID4) и возвращают
`{"query_id": ..., "status": "done" | "already_done", "result": ...}`.
`Notifications` дедуплицирует иначе — по содержимому запроса (см. `job_id`).

| Метод | Путь | Сервис | Тело запроса | Ответ |
| --- | --- | --- | --- | --- |
| `POST` | `/api/v1/get-message` | Backend | `{"user_id": int, "message": str}` | `{"state": str, "answer": str}` |
| `POST` | `/api/v1/send-message` | VK-Bot | `{"type": "message", "user_id": int, "message": str}` | `{"sent": true}` |
| `POST` | `/notifications` | Notifications | `{"type": "task"|"meeting", "date_notify": ISO-8601, "user_id": int, "title": str, "date": ISO-8601}` | `201 {"job_id": str}` |

Правила `Notifications`: `date_notify` должен быть в будущем и не позже `date`,
`title` — от 1 до 500 символов, `user_id > 0`. Одинаковый запрос даёт один и тот же
`job_id`, поэтому повторы не создают дубликатов.

---

<a name="модель-данных"></a>
## Модель данных

Схема создаётся из [Database/init.sql](Database/init.sql) при первой инициализации пустого
тома PostgreSQL.

- `user` — `user_id` (ID ВК), `username`, `timezone` (по умолчанию `Europe/Moscow`).
- `tasks` — задача или встреча: `type` (`task` / `meeting`), `title`, `raw_text`, `date`,
  `time`, `date_notify`, `is_notified` и `title_vector vector(768)`.
- `done_tasks` — обработанные `query_id`; защищает API от повторного выполнения.

Вектор заголовка (`paraphrase-multilingual-mpnet-base-v2`, 768 измерений, нормализованный)
используется для семантического поиска по истории: HNSW-индекс с косинусной метрикой,
кандидаты предварительно фильтруются по пользователю и периоду.

---

<a name="разработка-без-docker"></a>
## Разработка без Docker

Каждый модуль запускается отдельно; общая сеть нужна только для Docker.

```bash
# Backend — Python 3.12, зависимости из requirements.txt (torch ставится с CPU-индекса)
cd Backend
python -m venv .venv && . .venv/bin/activate
pip install torch --index-url https://download.pytorch.org/whl/cpu
pip install -r requirements.txt
export DATABASE_URL='postgresql+psycopg://postgres:пароль@localhost:5432/tasks_db'
export CREDENTIAL='<authorization key GigaChat>'
python main.py                              # http://localhost:8000
cd ..

# VK-Bot — Python 3.12, нужен ffmpeg для конвертации голосовых
cd VK-Bot
pip install -r requirements.txt
export VK_TOKEN='<токен сообщества>'
export HOST=localhost PORT=8000             # куда пересылать сообщения
python main.py                              # longpoll + HTTP на :80
cd ..

# Notifications — Python 3.13
cd Notifications
pip install -r requirements.txt
export POSTGRES_PASSWORD='<пароль>'
uvicorn app.main:app --host 0.0.0.0 --port 8080
cd ..

# Database — схема для новой пустой базы
psql "postgresql://postgres:<пароль>@localhost:5432/tasks_db" -f Database/init.sql
```

`Backend` и `VK-Bot` используют `pyproject.toml` + `uv.lock` (uv), а в образы ставятся
зафиксированные `requirements.txt`. Для `Notifications` тесты запускаются командой `pytest`
из каталога модуля.

---

<a name="тесты"></a>
## Тесты

Автотесты есть только у `Notifications` (29 тестов: FastAPI TestClient, планировщик
в памяти для юнит-тестов):

```bash
docker compose up -d postgres        # тестам API нужна доступная БД (см. «Быстрый старт»)
cd Notifications
pip install -r requirements.txt
POSTGRES_PASSWORD='<пароль БД>' pytest -q
```

Покрыты валидация запроса, идемпотентность планирования, повторы доставки, пропуск
устаревших напоминаний и форматирование сообщения. Остальные модули проверяются вручную:
реальный диалог с ботом и `docker compose logs`.

---

<a name="деплой"></a>
## Деплой

[.github/workflows/deploy.yml](.github/workflows/deploy.yml) при пуше в `main` (или вручную
из вкладки Actions) подключается к серверу по SSH, делает `git reset --hard origin/main`,
обновляет подмодули и выполняет `docker compose up -d --build`.

Секреты и переменные репозитория (Settings → Secrets and variables → Actions):

| Имя | Тип | Назначение |
| --- | --- | --- |
| `SERVER_HOST` | secret | IP или домен сервера |
| `SERVER_USER` | secret | Пользователь SSH |
| `SERVER_SSH_KEY` | secret | Приватный SSH-ключ целиком |
| `SERVER_PORT` | secret | Порт SSH (необязательно, по умолчанию 22) |
| `DEPLOY_PATH` | variable | Каталог проекта на сервере (по умолчанию `/opt/app`) |

`.env` на сервере workflow не создаёт и не перезаписывает — их нужно положить один раз
вручную. Для приватных подмодулей может понадобиться отдельный токен `SUBMODULES_TOKEN`
(закомментирован в workflow).

---

## Ограничения и особенности

- Состояние диалога (`IDLE` / `CLARIFY_DATE_NOTIFY`) хранится в памяти процесса бэкенда:
  при перезапуске сбрасывается и не разделяется между репликами. В коде оставлен план по
  переносу в таблицу `user`.
- Идемпотентность `VK-Bot` — тоже в памяти (TTL 24 часа); для нескольких экземпляров
  нужен общий стор.
- `init.sql` выполняется только при создании пустого тома. Изменения схемы требуют миграции
  или пересоздания тома `postgres_data` (данные будут потеряны).
- Тексты напоминаний форматируются по Москве (`Europe/Moscow`) независимо от часового
  пояса пользователя; планировщик работает в UTC.
- Сборка `Backend` требует интернета: модель эмбеддингов скачивается в образ, в рантайме
  `HF_HUB_OFFLINE=1`.
- `VK-Bot/.env` в compose обязателен (`env_file` без `required: false`): без файла модуль
  не запустится.

---

## Структура

```
GorkyCodeTest/
├── docker-compose.yml          # общий запуск всех модулей
├── Backend/                    # API, LLM, автомат диалога, работа с БД
│   └── README.md
├── Database/                   # Dockerfile PostgreSQL + pgvector и init.sql
│   └── README.md
├── Notifications/              # планировщик напоминаний и доставка в бота
│   └── README.md
├── VK-Bot/                     # Long Poll, STT (Vosk), HTTP-приёмник для отправки
│   └── README.md
└── .github/workflows/deploy.yml
```

<p align="center">
  <a href="#быстрый-старт">Быстрый старт</a> ·
  <a href="https://vk.ru/im/convo/-242449509?entrypoint=community_page&tab=all">ВК-беседа</a>
</p>
