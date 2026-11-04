# 内置敲字音效

三款音效均由项目内的合成程序生成，无需网络或外部声音文件。

- `soft.wav`：轻触，35 毫秒。
- `mechanical.wav`：机械键盘，65 毫秒。
- `typewriter.wav`：打字机，120 毫秒。

格式为 44.1 kHz、单声道、16 位 PCM WAV。运行 `python3 tool/generate_typing_sounds.py` 可重建这些素材。音量在载入时处理，敲字时播放已缓存的短音频；默认关闭。
