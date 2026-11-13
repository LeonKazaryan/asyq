# Asyq — асық ату

Казахская национальная игра в асыки для iPhone. 3D-кости из сканов настоящих асыков, физика, которая решает, каким боком ляжет кость, правила по Регламенту федерации, минималистичный интерфейс, slow-mo ударов и хаптика.

**v1.0** (цель — Наурыз 2027): «Бес табан» и Шыр «Алшы» против ботов, иіру, обучение и справочник «Ереже». Онлайн — с v1.2.

## Запуск

1. Открыть `Asyq.xcodeproj` в Xcode 27.
2. Таргет **Asyq** → Signing & Capabilities → выбрать свою команду.
3. Выбрать iPhone или симулятор iPhone 16 Pro (iOS 18.6) → `⌘R`. Тесты — `⌘U`.

## Документы

| Файл | О чём |
|---|---|
| [docs/01-product.md](docs/01-product.md) | Видение, аудитория, скоуп v1.0, экраны, открытые вопросы |
| [docs/02-design.md](docs/02-design.md) | Арт-дирекшн, motion, хаптика, звук, вау-моменты, обучение |
| [docs/03-architecture.md](docs/03-architecture.md) | Стек, слои, физика и детерминизм, бот, журнал решений (ADR) |
| [docs/04-roadmap.md](docs/04-roadmap.md) | Этапы M0–M10 с датами и чек-листами |
| [docs/05-rules.md](docs/05-rules.md) | Правила, которые реализует игра, и спорные места |
| [docs/06-conventions.md](docs/06-conventions.md) | Код, git, как работаем вместе |
| [docs/07-apple-rules.md](docs/07-apple-rules.md) | HIG, App Review, чек-лист |
| [docs/research/](docs/research/) | Исходный ресёрч: правила с источниками и большой гейм-дизайн |

## Стек

Swift 6 · SwiftUI · Metal · Jolt Physics · Core Haptics · AVAudioEngine · SwiftData · Swift Testing. iOS 18+, iPhone, портрет.
