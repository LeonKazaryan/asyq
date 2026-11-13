# Asyq — правила для Claude

iOS-игра в казахский асық ату: 3D-кости из сканов, настоящая физика (Jolt), правила по Регламенту федерации, минималистичный интерфейс, сильные анимации и хаптика. В v1.0 игра против ботов («Бес табан» и Шыр «Алшы»), онлайн — с v1.2. Цель — релиз в App Store к Наурызу 2027.

## Перед задачей

- Прочитай нужные документы в `docs/`:
  - `01-product.md` — скоуп v1.0;
  - `02-design.md` — арт-дирекшн, motion, хаптика, вау-моменты;
  - `03-architecture.md` — слои, физика, детерминизм, ADR;
  - `05-rules.md` — **спецификация правил**. Код в `Rules/` и `Judge` следует только ей.
- Задачи берём из `docs/04-roadmap.md`. Держись скоупа текущего этапа.
- Исходный ресёрч (рабочее название тогда «Сақа») — в `docs/research/`. Если расходится с `docs/01–07`, верны они.

## Общение

- Отвечай Leon по-русски. Код, идентификаторы, комментарии и сообщения коммитов — на английском. Казахские термины в коде — транслитерацией (таблица в `docs/06-conventions.md`).
- Leon новичок в iOS. Новую iOS/Swift/Metal-концепцию объясни в 1–2 фразах, по делу.
- Продуктовое или дизайн-решение — предложи вариант с рекомендацией, а не список.

## Сборка и проверка

После изменений кода **всегда** проверяй сборку и тесты:

```bash
xcodebuild -project Asyq.xcodeproj -scheme Asyq \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' -quiet build

xcodebuild -project Asyq.xcodeproj -scheme Asyq \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' -quiet test
```

- `OS=18.6` обязателен: без него Xcode ищет iPhone 16 Pro на последней iOS. На iOS 26 — `name=iPhone 17 Pro`, на iOS 27 — `name=iPhone 18 Pro`.
- Сборка без ошибок и без новых warnings.
- Бросок, анимации, хаптику и звук проверить не можешь: скажи Leon, что именно попробовать на iPhone. Симулятор рисует не выше 60 fps и не даёт хаптики.

## Правила

- **Не коммить.** Коммитит Leon. Можно предложить текст коммита (Conventional Commits).
- **Сторонние зависимости:** только Jolt (ADR-002). Любую другую — только с согласия Leon и с записью ADR.
- **Файлы проекта:** `Asyq/` и `AsyqTests/` — синхронизированные папки (Xcode 16+). Новые файлы просто создавай в нужной подпапке, `project.pbxproj` не трогай. Ручная правка `project.pbxproj` — только для build settings и подключения `Packages/`.
- **Swift 6, iOS 18.** Strict concurrency. API новее — под `if #available`.
- **Правила игры.** Любое толкование Регламента или отступление от него записывай в `docs/05-rules.md` со статусом и страницей. Не придумывай правила молча.
- **`Rules/` — чистый Swift** без UIKit, Metal и физики. Покрытие тестами на каждый пункт спецификации.
- **Числа ощущений и физики** (пружины, силы, трение, пороги, slow-mo) — только в `Tuning/GameTuning.swift`.
- **DesignSystem-токены** вместо магических чисел в фичах (появятся в M2).
- **Детерминизм.** Симуляция не зависит от времени кадра, `Date()`, `random()` без сида и порядка словарей. Всё, что задаёт бросок или судит итог (скорости, начальные позы, стороны, «выбит»), считается через `SimMath`, а не через simd-хелперы и libm (ADR-002). Тест детерминизма должен оставаться зелёным.
- **Reduce Motion** — в каждой новой анимации.
- **Обновляй доки:** галочки в роадмапе, решения в журнал ADR (`03-architecture.md`).
- **Правила Apple** — `docs/07-apple-rules.md`, чек-лист перед мержем. Если задача упирается в правило Apple, скажи Leon явно.

## Проверка без касаний (DEBUG launch-аргументы)

```bash
xcrun simctl launch --terminate-running-process "iPhone 16 Pro" com.leonkazaryan.asyq -AsyqDebugThrow 0,0.64
xcrun simctl io "iPhone 16 Pro" screenshot shot.png
```

- `-AsyqDebugThrow угол°,сила[,подкрутка]` — бросает сам через 1,2 с. Отрицательный угол не передать (значение с «-» читается как новый флаг).
- `-AsyqDebugPull сила,прицел` — держит рогатку натянутой, видно предпросмотр.
- `-AsyqDebugFromEdge YES` — бросок с края круга.
- `-AsyqDebugCategory bala|jasospirim|jigit|eresek` — категория.
- Счётчик кадров внизу слева — только в Debug.

## Переиспользование из Nomaded

Nomaded (`~/projects/nomaded`) — первое приложение Leon, там уже есть Metal-рендер (`GlobeEngine/GlobeMetalView.swift`), `SpringValue`, `Motion`, `Haptics`, `Glass`, `HeroNumber`, генератор иконки и скриншотов в `Tools/`. Код переносим копированием с адаптацией под Asyq, а не общим пакетом.

## Окружение

- Xcode 27.2, симуляторы iOS 18.6 (iPhone 16 Pro, основной), 26.3 (iPhone 17 Pro), 27.2 (iPhone 18 Pro).
- Bundle ID: `com.leonkazaryan.asyq`, команда та же, что у Nomaded.
- Репозиторий: https://github.com/LeonKazaryan/asyq
