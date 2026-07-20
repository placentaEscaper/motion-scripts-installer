# Встановлення та використання projectifier

## Крок 1. Отримай доступ до репозиторію (GitHub токен)

Репозиторій `placentaEscaper/projectifier` приватний, тому знадобиться токен.

1. Перейди на https://github.com/settings/personal-access-tokens/new
2. Заповни:
   - **Resource owner:** `placentaEscaper`
   - **Repository access:** Only select repositories → `projectifier`
   - **Permissions → Repository permissions → Contents:** `Read-only`
3. Натисни **Generate token**.
4. Скопіюй токен (`github_pat_...`) одразу — вдруге його побачити не можна.

## Крок 2. Запусти інсталер

```bash
chmod +x install.sh
./install.sh
```

Якщо запитає встановити Homebrew — натисни `y`. Коли запросить токен — встав той, що скопіював у Кроці 1 (введення прихованим, символи не відображаються — це нормально).

Після завершення **відкрий новий термінал** (або виконай `source ~/.zshrc` чи `source ~/.bash_profile`).

## Крок 3. Постав секрети, яких немає в репозиторії

Ці файли в `.gitignore`, тому їх треба покласти вручну — інсталер сам їх не створює.

**Обов'язково — Airtable токен:**

```bash
mkdir -p ~/.local/bin/projectifier/env
echo "TOKEN=<твій Airtable Personal Access Token>" > ~/.local/bin/projectifier/env/.env
```

Токен для Airtable створюється тут: https://airtable.com/create/tokens

**Опційно — якщо користуєшся вивантаженням файлів з Google Drive** (поле "Related creative" в задачі):

Поклади OAuth client secret з Google Cloud Console у файл:
```
~/.local/bin/projectifier/env/credentials.json
```
При першому зверненні до Google Drive програма сама відкриє браузер для авторизації і збереже токен доступу в `env/token.pickle` — це теж не треба робити вручну.

## Крок 4. Перший запуск

```bash
prj
```

При першому запуску програма запитає посилання на Airtable-view прямо в терміналі:
```
Please insert link to your view:
```
Встав посилання і натисни Enter. Воно збережеться в `~/.config/projectifier/configs.txt`, і наступного разу вводити знову не треба — `prj` одразу підхопить збережене посилання.

## Повсякденне використання

Просто вводь в терміналі:
```bash
prj
```

## Оновлення

- **Автоматично:** `prj` сам раз на добу перевіряє, чи вийшла нова версія на гілці `main`, і якщо так — підтягує зміни та перевстановлює залежності перед запуском.
- **Примусово прямо зараз:**
  ```bash
  prj --update
  ```

## Якщо щось пішло не так

- **`prj: command not found`** — не відкрив новий термінал після встановлення, або `~/.local/bin` не потрапив у PATH. Виконай `source ~/.zshrc` (або `~/.bash_profile`) і спробуй ще раз.
- **Помилка доступу до репозиторію під час встановлення** — токен протермінований, або в ньому не увімкнено `Contents: Read-only` саме для `projectifier`. Створи новий токен (Крок 1) і запусти `./install.sh` ще раз.
- **Програма падає з помилкою про `TOKEN`** — забув створити `env/.env` (Крок 3).
- **Хочеш переустановити з нуля:** просто запусти `./install.sh` ще раз — він примусово підтягне останню версію коду з `main`.
