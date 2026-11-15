# Asuna Ai iOS 10

Нативное приложение для iPad (iOS 10, jailbreak) с персонажем Asuna на Live2D Cubism 2.1 и интерфейсом в стиле Liquid Glass.

## Возможности

- Отрисовка Live2D-модели (OpenGL ES 1.1 / GLKit), 52 образа с переключением прямо в приложении
- Живое поведение: смена idle-анимаций и выражений, реакции на тап, слежение взгляда за пальцем
- Жесты и позы, управляемые действиями модели (повороты, кивки, приветствия и др.)
- Синхронизация губ с речью (системный синтезатор AVSpeechSynthesizer)
- Чат с историей, окно ввода с поддержкой клавиатуры, голосовой ввод (PTT, распознавание речи)
- Настройки: выбор провайдера/модели, адрес прокси, фон, локальный TTS

## Сборка

Требуется Linux-сборка через `linuxios.py` и SDK iPhoneOS 10.3:

```bash
cd LinuxiOSBuilder
python3 linuxios.py build \
  --project AsunaLiquidGlass \
  --name AsunaLiquidGlass \
  --bundle-id com.alexius.asuna.liquidglass \
  --sdk sdks/theos-sdks/iPhoneOS10.3.sdk
```

Результат: `AsunaLiquidGlass/build/AsunaLiquidGlass.ipa` (бинарь подписывается `ldid -S`, установка зависит от инструментов джейлбрейка).

## Установка на устройство

```bash
# пример через SSH (OpenSSH на устройстве)
tar -C AsunaLiquidGlass/build/Payload/AsunaLiquidGlass.app -cf - . | \
  ssh -p 2222 root@<device> 'tar -xf - -C /Applications/AsunaLiquidGlass.app && \
  chown -R mobile:mobile /Applications/AsunaLiquidGlass.app && \
  chmod 755 /Applications/AsunaLiquidGlass.app/AsunaLiquidGlass'
```

## Структура

- `main.m` — UI, чат, настройки, голосовой ввод и синтез речи
- `AsunaLive2DView.h/.mm` — загрузка и рендеринг Live2D, анимации, выражения, жесты
- `models/` — ресурсы моделей (`.moc`, текстуры, `mtn`, `exp`, `physics`)
- `live2d_native/` — нативная библиотека/заголовки Live2D
