# Полное руководство по извлеченным библиотекам и ресурсам Asuna (Sword Art Online Wake-Up)

Все компоненты, библиотеки и ресурсы разложены в директории:
`file:///home/alexius/Projects/asuna/extracted_libraries/`

---

## 1. Структура извлеченных библиотек

```
extracted_libraries/
├── dex/
│   └── classes.dex               # Байткод Java со всеми SDK (Live2D SDK 2.x, Toshiba TTS Java wrapper, Sony SAgent)
├── live2d_models/                # 52 полных костюма/модели Асуны формата Live2D Cubism 2.1
│   ├── asuna_01/                 # Рыцарский костюм Ордена Рыцарей Крови (KoB)
│   │   ├── asuna_01.model.json   # Главный манифест модели (текстуры, физика, эмоции, анимации, hit_areas)
│   │   ├── asuna_01.physics.json # Физика волос и одежды
│   │   ├── exp/                  # 10 JSON-файлов лицевых выражений (F_FUN, F_ANGRY, F_SAD, F_SMILE и др.)
│   │   ├── moc/                  # Модель геометрии (.moc) и текстурные атласы (1024x1024 PNG)
│   │   └── mtn/                  # 19 файлов анимаций (.mtn): дыхание, злость, радость, чихание и т.д.
│   └── asuna_02 ... asuna_56/    # Остальные костюмы (школьная форма, пижама, купальник, свитер и др.)
├── native_libs/
│   └── armeabi/
│       ├── libTtsToSpeakG3V1_JP.so          # Ядро синтезатора речи Toshiba ToSpeak G3
│       ├── libToSpeakTtsSynthProxyG3V1JP.so  # JNI-мост и OpenSLES-вывод для Android
│       └── libtospeakuserlex_JP.so          # Библиотека пользовательского лексикона ToSpeak
└── tts_toshiba_data/
    ├── data-install-config
    ├── jaJP_langDic_n40c.dicL               # Языковой словарь японского языка (фонетика, морфология)
    ├── jaJP_voiceDic_DF_FHT000H3.dicL       # Акустическая модель голоса Haruka Tomatsu (Асуна)
    ├── jaJP_prosDic_TR_FHT000H3.dicL        # Модель просодии и интонаций
    └── libtts_uselimit.bin                  # Бинарная лицензия движка (256 байт)
```

---

## 2. Библиотека Live2D (Cubism SDK 2.1)

### Что это за библиотека:
В приложении используется **Live2D Cubism SDK 2.1**.
- Вся логика рендеринга и анимации выполнена на чистом Java/OpenGL ES (пакет `jp.live2d.*`), поэтому нативные `.so` библиотеки для Live2D в данном APK не требуются.
- В `classes.dex` присутствуют все 122 класса SDK:
  - `jp.live2d.Live2D` — инициализация среды;
  - `jp.live2d.ALive2DModel` / `jp.live2d.android.Live2DModelAndroid` — загрузка геометрии `.moc` и привязка OpenGL-текстур;
  - `jp.live2d.motion.Live2DMotion` — парсинг и воспроизведение анимаций `.mtn`;
  - `jp.live2d.physics.PhysicsHair` — расчет физики покачивания волос и одежды;
  - `com.mezamane.asuna.app.LAppLive2DManager` — высокоуровневый менеджер взаимодействия с персонажем (обработка касаний по зонам `head`, `chest`, `body`, `foot`).

### Как использовать модели Асуны:

#### Вариант А: В веб-браузере (Web / Electron / PixiJS)
Все 52 модели (`asuna_01` — `asuna_56`) являются стандартными моделями формата Cubism 2.1 (`.moc` + `.model.json` + `.mtn`):
1. Используйте библиотеку `pixi-live2d-display` (cubism2) или официальный `live2d.min.js` (Cubism 2.1 Web SDK).
2. Загрузка в JavaScript:
   ```javascript
   import * as PIXI from 'pixi.js';
   import { Live2DModel } from 'pixi-live2d-display/cubism2';

   const app = new PIXI.Application({ width: 800, height: 1000, transparent: true });
   document.body.appendChild(app.view);

   const model = await Live2DModel.from('extracted_libraries/live2d_models/asuna_01/asuna_01.model.json');
   app.stage.addChild(model);

   // Запуск анимации ожидания:
   model.motion('idle', 0);
   // Запуск выражения лица:
   model.expression('F_FUN_SMILE');
   ```

#### Вариант Б: В Android / Java приложении
1. Подключите классы `jp.live2d.*` из `classes.dex` или официальный `live2d-android-sdk-2.1.jar`.
2. Рендеринг в `GLSurfaceView.Renderer`:
   ```java
   Live2D.init();
   Live2DModelAndroid model = Live2DModelAndroid.loadModel(inputStream);
   model.setTexture(textureNo, glTextureId);
   model.update();
   model.draw(gl);
   ```

---

## 3. Toshiba ToSpeak G3 TTS (Синтезатор речи)

### Что это за библиотеки:
- `libTtsToSpeakG3V1_JP.so`: Главный нативный C++ движок акустического синтеза речи по скрытым марковским моделям/текстовым правилам (HMM-based speech synthesis).
- `libToSpeakTtsSynthProxyG3V1JP.so`: JNI-интерфейс для Android, отвечающий за связь Java $\leftrightarrow$ C++ и вывод через AudioTrack / OpenSLES.
- `libtospeakuserlex_JP.so`: Подсистема пользовательских словарей и акцентов.
- Файлы данных (`tts_toshiba_data/`):
  - `jaJP_voiceDic_DF_FHT000H3.dicL` + `jaJP_prosDic_TR_FHT000H3.dicL` — тембр и интонация Асуны (Харука Томацу).
  - `libtts_uselimit.bin` — лицензионный токен авторизации API.

### Что им нужно для работы:
1. **Архитектура:** 32-битный ARM (`armeabi-v7a` / совместимый ARM64 с поддержкой 32-бит).
2. **Файловая структура:** trailing slash в конфигах путей (`config = "dir1/\tdir2/\tdir3/"`).
3. **Лицензионная инициализация:** передача ключей `libLimitKey0..7`, `voiceDicLimitKey0..7_sv`, `prosDicLimitKey0..7_sv` и 256 байт из `libtts_uselimit.bin`.
4. **Кодировка текста:** только **CP932 / Shift-JIS** (нативно используется японской кодовой базой ToSpeak).
5. **Алиас голоса:** в движке зашит дефолтный код `FKN000H1`, поэтому создаются симлинки:
   `jaJP_voiceDic_DF_FKN000H1.dicL` $\to$ `jaJP_voiceDic_DF_FHT000H3.dicL`
   `jaJP_prosDic_TR_FKN000H1.dicL` $\to$ `jaJP_prosDic_TR_FHT000H3.dicL`.

### Как использовать:
- Мы написали готовый драйвер `asuna_tts.c` (скомпилирован в `asuna_tts_arm`), который вызывает методы ядра:
  ```c
  fn_init(engine, synth_callback, config);
  fn_setProperty(engine, "libinfo", license_bytes, 256);
  fn_setLanguage(engine, "jpn", "JPN", "");
  fn_doSetSynth(shift_jis_text);
  fn_doGenerateWave(pcm_buffer, size, NULL);
  ```
- Аудиопоток отдается с частотой **22050 Гц, 16-бит моно PCM**.

---

## 4. Sony SAgent Framework (`com.sony.csx.sagent`)

### Что это за библиотека:
Фирменный фреймворк умного ассистента от Sony Mobile Communications:
- **Управление диалогом:** сценарии и триггеры расписания, погоды, будильника (`recipe_manager`).
- **Связка Речь $\leftrightarrow$ Персонаж:** синхронизация звуковых пауз с движением губ Live2D (`LAppLive2DManager.setLipSync`) и выражениями лица.
- **Поддержка распознавания речи:** абстракция `speech_recognizer_ex` над Google Speech API.
