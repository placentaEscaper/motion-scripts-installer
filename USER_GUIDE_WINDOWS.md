# Встановлення та використання projectifier (Windows)

## Крок 1. Отримай доступ до репозиторію (GitHub токен)

Репозиторій `placentaEscaper/projectifier` приватний, тому знадобиться токен.

1. Перейди на https://github.com/settings/personal-access-tokens/new
2. Заповни:
   - **Resource owner:** `placentaEscaper`
   - **Repository access:** Only select repositories → `projectifier`
   - **Permissions → Repository permissions → Contents:** `Read-only`
3. Натисни **Generate token**.
4. Скопіюй токен (`github_pat_...`) одразу — вдруге його побачити не можна.

## Крок 2. Запусти інсталятор

Відкрий **PowerShell** (не cmd.exe) і виконай:

```powershell
powershell -ExecutionPolicy Bypass -File install_2.ps1
```

(`-ExecutionPolicy Bypass` потрібен лише для цього запуску — Windows за замовчуванням блокує виконання нескопійованих `.ps1`-скриптів; на систему в цілому це ніяк не впливає.)

Якщо `winget` не знайдено — постав "App Installer" з Microsoft Store (https://aka.ms/getwinget) і запусти інсталятор ще раз. Коли запросить токен — встав той, що скопіював у Кроці 1 (введення прихованим, символи не відображаються — це нормально).

Після завершення **відкрий новий термінал** (PowerShell перечитає PATH автоматично).

## Крок 3. Постав секрети, яких немає в репозиторії

Ці файли в `.gitignore`, тому їх треба покласти вручну — інсталятор сам їх не створює.

**Обов'язково — Airtable токен:**

```powershell
New-Item -ItemType Directory -Force -Path "$env:LOCALAPPDATA\Programs\projectifier\projectifier\env"
Set-Content -Path "$env:LOCALAPPDATA\Programs\projectifier\projectifier\env\.env" -Value "TOKEN=<твій Airtable Personal Access Token>"
```

Токен для Airtable створюється тут: https://airtable.com/create/tokens

**Опційно — якщо користуєшся вивантаженням файлів з Google Drive** (поле "Related creative" в задачі):

Поклади OAuth client secret з Google Cloud Console у файл:
```
%LOCALAPPDATA%\Programs\projectifier\projectifier\env\credentials.json
```
При першому зверненні до Google Drive програма сама відкриє браузер для авторизації і збереже токен доступу в `env\token.pickle` — це теж не треба робити вручну.

## Крок 4. Перший запуск

```powershell
prj
```

При першому запуску програма запитає посилання на Airtable-view прямо в терміналі:
```
Please insert link to your view:
```
Встав посилання і натисни Enter. Воно збережеться в `%LOCALAPPDATA%\projectifier\configs.txt`, і наступного разу вводити знову не треба — `prj` одразу підхопить збережене посилання.

За замовчуванням `prj` спостерігає за теками проєктів у `D:\Projects` (якщо диска `D:` немає — створи його або зверни увагу на помилку при першому запуску).

## Повсякденне використання

Просто вводь у терміналі (PowerShell або cmd — команда працює в обох):
```powershell
prj
```

## Оновлення

- **Автоматично:** `prj` сам раз на добу перевіряє, чи вийшла нова версія на гілці `main`, і якщо так — підтягує зміни та перевстановлює залежності перед запуском.
- **Примусово прямо зараз:**
  ```powershell
  prj --update
  ```

## Якщо щось пішло не так

- **`prj: команду не розпізнано`** — не відкрив новий термінал після встановлення. Закрий і відкрий термінал наново і спробуй ще раз.
- **`winget` не знайдено** — постав "App Installer" з Microsoft Store (https://aka.ms/getwinget) або онови Windows, тоді запусти `install_2.ps1` ще раз.
- **Скрипт не запускається / пише про Execution Policy** — запускай саме через `powershell -ExecutionPolicy Bypass -File install_2.ps1`, а не подвійним кліком.
- **Помилка доступу до репозиторію під час встановлення** — токен протермінований, або в ньому не увімкнено `Contents: Read-only` саме для `projectifier`. Створи новий токен (Крок 1) і запусти `install_2.ps1` ще раз.
- **Програма падає з помилкою про `TOKEN`** — забув створити `env\.env` (Крок 3).
- **Хочеш переустановити з нуля:** просто запусти `install_2.ps1` ще раз — він примусово підтягне останню версію коду з `main`.

## Де що лежить (для довідки)

| Що | Шлях |
|---|---|
| Код застосунку (git checkout) | `%LOCALAPPDATA%\Programs\projectifier\projectifier` |
| Команда `prj` (`prj.ps1` + `prj.cmd`) | `%LOCALAPPDATA%\Programs\projectifier\bin` |
| Токен GitHub, службові файли інсталятора | `%LOCALAPPDATA%\Programs\projectifier\.installer` |
| Конфіги застосунку (`configs.txt`, темплейт-проєкт) | `%LOCALAPPDATA%\projectifier` |
| Тека проєктів (за замовчуванням) | `D:\Projects` |

Перші дві та третя тека — службові, чіпати їх вручну не потрібно.
