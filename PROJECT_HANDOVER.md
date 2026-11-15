# Asuna Liquid Glass — База знаний и Handover Досье Проекта

> **Статус проекта**: Активная разработка / Отладка Live2D WebGL рендеринга на iOS 10.3.3.  
> **Целевое устройство**: Apple iPad mini 2 (Wi-Fi + Cellular, `iPad4,5`), Retina 1536x2048, SoC Apple A7 (ARM64), GPU Imagination PowerVR G6430, iOS 10.3.3 (Jailbroken: doubleH3lix / h3lix).  
> **Хост разработки**: Linux (Arch Linux / Fedora / Ubuntu), x86_64.

---

## 1. Главные правила и ограничения (Strict Rules)

1. **Запрет несогласованных перезагрузок**:
   - **НИКОГДА НЕ ПЕРЕЗАГРУЖАТЬ** iPad или ПК (`reboot`, `ldrestart`, `killall SpringBoard`, рестарт системы) без явного прямого подтверждения от пользователя в чате. Правило внесено глобально в `/home/alexius/.gemini/GEMINI.md`.
2. **Локальный оффлайн-запуск на iPad**:
   - Все веб-ассеты (HTML, PixiJS, Live2D Cubism 2, скрипты, шейдеры и 52 модели Асуны) хранятся локально в бандле приложения `/Applications/AsunaLiquidGlass.app/www/` и обслуживаются встроенным легковесным сокетом на `127.0.0.1:8999`.
   - Внешний/удаленный сервер используется **только** для AI-проксирования запросов (Gemini / OpenRouter / STT Whisper) и вообще не нагружается графикой или моделями.
3. **Обязательное тестирование рендеринга на ПК перед деплоем**:
   - Любые изменения в шейдерах, логике мешей или библиотеках сначала визуально тестируются на ПК через headless Chromium / Playwright, сохраняя тестовый скриншот, и только затем отправляются на планшет.

---

## 2. Структура проекта и ключевые файлы

### Корневые пути:
- **Проект iOS**: `/home/alexius/Projects/LinuxiOSBuilder-full-starter/LinuxiOSBuilder/AsunaLiquidGlass`
- **Тулчейн сборки без macOS**: `/home/alexius/Projects/LinuxiOSBuilder-full-starter/LinuxiOSBuilder`
  - Скрипт сборщика: `linuxios.py`
  - Clang/LLVM: `toolchain/linux/iphone/bin/clang` (target `arm64-apple-ios10.0`)
  - iOS SDK: `sdks/theos-sdks/iPhoneOS10.3.sdk`
  - Подпись: `toolchain/linux/iphone/bin/ldid -S`
- **Эталонный Android APK**: `/home/alexius/Downloads/Asuna-Liquid-Glass.apk` (исходники веб-аватара лежат в `assets/avatar/` и `assets/resources/models/`).
- **Сниппет веб-версии**: `/home/alexius/Projects/asuna-web/`

### Структура `AsunaLiquidGlass`:
- `main.m`: Нативный код приложения Objective-C:
  - Встроенный многопоточный BSD HTTP-сервер на C-сокетах (`127.0.0.1:8999`):
    - Отдает оффлайн файлы из `www/`.
    - Эндпоинт `POST /save_snap` — принимает Base64 DataURL из WebGL канваса и сохраняет в `/tmp/asuna_canvas.png`.
    - Эндпоинт `POST /log` — логирует консольные вызовы WebView в `/tmp/asuna_web.log`.
    - Эндпоинт `GET /snap.png` — делает скриншот иерархии окон iOS через `drawViewHierarchyInRect:`.
  - `AsunaMainViewController`: Главный экран:
    - Градиентная подложка Liquid Glass (5 пресетов: Obsidian, SAO Sunset, Cyberpunk, Lavender, OLED Black).
    - `UIImageView *_customBgImageView` — слой пользовательских обоев поверх градиента.
    - `WKWebView *_live2dWebView` с прозрачным фоном, загружает `http://127.0.0.1:8999/index.html`.
    - Всплывающий Liquid Glass баббл реплик (по умолчанию скрыт на старте, открывается при ответах ИИ/голосовом вводе).
    - Парящий капсульный стеклянный Dock Bar: Chat Drawer, смена скина/модели, центральная светящаяся PTT-сфера, переключатель Gemini/OpenRouter, кнопка Настроек.
    - Поддержка нативного синтеза речи iOS (`AVSpeechSynthesizer`, голос `ru-RU`) с липсинком рта (`emitMouth`).
  - `ModelsSettingsViewController`: Настройки:
    - Секция 0: «ОФОРМЛЕНИЕ И ФОН» — выбор собственных обоев из галереи через `UIImagePickerController` (сохраняется в `Documents/custom_bg.png`) и сброс на Liquid Glass.
    - Секция 1: Синтез речи iPad (TTS вкл/выкл).
    - Секция 2: URL AI-прокси.
    - Секция 3: Провайдер и ключи Gemini/OpenRouter.
    - Секция 4: Отображение квот и лимитов.
    - Секция 5: Выбор нейросетевых моделей из динамического списка.
- `www/`:
  - `index.html` — холст WebGL, фоновая аура SVG, скрипты.
  - `libs/pixi.min.js` — PixiJS v6.5.2.
  - `libs/live2d.min.js` — Cubism 2.1 Core Runtime (размер ~129 КБ).
  - `libs/cubism2.min.js` — Pixi Live2D плагин (cubism2 integration).
  - `models/` — 52 локальные модели Live2D (`asuna_01` ... `asuna_56`).
  - `app.js`, `asuna-shim.js`, `motion-engine.js`, `gestures.js`, `tilt-physics.js` — скрипты взаимодействия, физики и анимации.

---

## 3. Мост связи с планшетом (iPad USB / SSH)

- **Физическое подключение**: iPad подключен по USB-кабелю к ПК.
- **Туннелирование портов**: На хосте запущен бесконечный цикл `iproxy 2222 22`:
  ```bash
  # Доступ по SSH:
  sshpass -p alpine ssh -p 2222 root@127.0.0.1 "<command>"
  ```
- **Команды управления приложением на iPad**:
  - Убийство зависшего процесса: `killall -9 AsunaLiquidGlass 2>/dev/null || true`
  - Запуск от пользователя mobile: `su -c 'openapp com.alexius.asuna.liquidglass' mobile`
  - Снятие нативного скриншота экрана: `snap /tmp/screenshot.png`
  - Чтение скриншота на ПК через SSH поток:
    ```bash
    sshpass -p alpine ssh -p 2222 root@127.0.0.1 "cat /tmp/screenshot.png" > screenshot.png
    ```
  - Получение WebGL-снимка модели:
    ```bash
    sshpass -p alpine ssh -p 2222 root@127.0.0.1 "cat /tmp/asuna_canvas.png" > canvas.png
    ```

---

## 4. Сборка и деплой

Сборка из корневой папки сборщика:
```bash
cd /home/alexius/Projects/LinuxiOSBuilder-full-starter/LinuxiOSBuilder && \
python3 linuxios.py build \
  --project AsunaLiquidGlass \
  --name AsunaLiquidGlass \
  --bundle-id com.alexius.asuna.liquidglass \
  --sdk sdks/theos-sdks/iPhoneOS10.3.sdk
```

Быстрая накатка бинарника и измененных веб-файлов прямо на планшет:
```bash
cd /home/alexius/Projects/LinuxiOSBuilder-full-starter/LinuxiOSBuilder/AsunaLiquidGlass/build/Payload/AsunaLiquidGlass.app && \
tar -cf - AsunaLiquidGlass www/index.html www/libs/live2d.min.js | \
sshpass -p alpine ssh -p 2222 root@127.0.0.1 \
  "tar -xpf - -C /Applications/AsunaLiquidGlass.app && chown -R mobile:mobile /Applications/AsunaLiquidGlass.app && chmod 755 /Applications/AsunaLiquidGlass.app/AsunaLiquidGlass"
```

Перезапуск:
```bash
sshpass -p alpine ssh -p 2222 root@127.0.0.1 \
  "killall -9 AsunaLiquidGlass 2>/dev/null || true; su -c 'openapp com.alexius.asuna.liquidglass' mobile"
```

---

## 5. Расследование бага «Сломанные текстуры / кубизм скина»

### Симптомы:
- На ПК в Chromium (`pc_asuna_clean.png`) модель Асуны отрисовывается **идеально и чисто**.
- На iPad mini 2 в WKWebView (`ipad_canvas_fresh.png`) полигоны и текстуры отрисовываются фрагментированными треугольниками/прямоугольниками («кубизм»), части текстур разорваны и смещены.

### Анализ и архитектура Live2D Cubism 2.1:
1. **Шейдеры `loadShaders2` в `live2d.min.js`**:
   - Были изначально объявлены как `precision mediump float;`.
   - На мобильных GPU PowerVR (Apple A7) `mediump` имеет пониженную точность (16-bit half float), из-за чего координаты интерполяции текстур $UV$ ($v\_texCoord$) округляются с огромной погрешностью, вызывая ступени и разрывы.
   - Мы пропатчили фрагментные и вершинные шейдеры в `live2d.min.js` на `precision highp float;`.
2. **Индексные буферы WebGL (`drawElements`)**:
   - В оригинальном `live2d.min.js` индексы создавались как `new Int16Array(...)`, а в `gl.drawElements` передавался `gl.UNSIGNED_SHORT`. В движке WebKit на iOS знаковый `Int16Array` приводил к искажениям. Замена на `Uint16Array` выполнена.
3. **Обнаруженный механизм профилей в `live2d.min.js`**:
   - Внутри библиотеки есть функция `r.setup()` и `Q.initProfile()`.
   - При обнаружении iOS (`r.isIOS()` проверяет `iPhone` или `iPad` по `navigator.userAgent`), Live2D автоматически применяет `Q.PROFILE_IOS_DEFAULT` (`USE_ADJUST_TRANSLATION: true`, `EXPAND_W: 2/4`).
   - На десктопе и Android применяется профиль `PROFILE_DESKTOP` / `PROFILE_ANDROID` (`USE_ADJUST_TRANSLATION: false`).
   - В `www/libs/live2d.min.js` мы принудительно выставили `USE_ADJUST_TRANSLATION: false` для всех профилей.
4. **Контекст WebGL 1 vs WebGL 2 в iOS 10.3 WKWebView**:
   - iOS 10.3 WKWebView поддерживает WebGL 1.
   - Важно убедиться, что `PIXI.settings.PRECISION_VERTEX = PIXI.PRECISION.HIGH;` и `PIXI.settings.PRECISION_FRAGMENT = PIXI.PRECISION.HIGH;` активны в начале `app.js` до создания `PIXI.Application`.

---

## 6. Что готово и что делать дальше

### Готово:
- [x] Полностью рабочий нативный интерфейс Liquid Glass, стеклянный док и PTT кнопка.
- [x] Приветственная надпись скрыта на старте (`_speechBubblePill.hidden = YES`).
- [x] Добавлена смена фона на любое пользовательское фото из галереи в Настройках (`UIImagePickerController`).
- [x] Локальный HTTP-сервер на C-сокетах (`127.0.0.1:8999`) на планшете.
- [x] Автоматический пайплайн получения снимков канваса (`/tmp/asuna_canvas.png`) и экрана (`snap /tmp/screenshot.png`).
- [x] Пропатчен `live2d.min.js` (`precision highp float`, `Uint16Array`).

### Следующие шаги для продолжающего агента:
1. **Проверить рендеринг после последней правки шейдеров `precision highp float;`**:
   - Задеплоить пропатченный `live2d.min.js` на планшет (`tar | ssh`).
   - Сделать снимок `/tmp/asuna_canvas.png` и проверить, исчезли ли артефакты геометрии.
2. **Если артефакт сохраняется**:
   - Проверить в `www/app.js` параметры инициализации `PIXI.Application`:
     - Добавить `PIXI.settings.PRECISION_VERTEX = 'highp';` и `PIXI.settings.PRECISION_FRAGMENT = 'highp';`.
     - Проверить `antialias: false` vs `true` и `preserveDrawingBuffer: true`.
   - Проверить флаг `textureFlipY` в `cubism2.min.js`: на iOS WKWebView инверсия по Y в связке с Pixi иногда дублируется, если текстура загружается через ImageLoader PixiJS.
   - В крайнем случае, как альтернатива устаревшему WebGL-хаку Cubism 2.1 — задействовать canvas 2D fallback renderer или готовый WebGL рендерер из официального SDK Cubism 2.1.
