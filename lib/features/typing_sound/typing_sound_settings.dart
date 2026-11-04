enum TypingSoundPreset {
  off('关闭', null),
  soft('轻触', 'assets/sounds/soft.wav'),
  mechanical('机械键盘', 'assets/sounds/mechanical.wav'),
  typewriter('打字机', 'assets/sounds/typewriter.wav');

  const TypingSoundPreset(this.label, this.asset);
  final String label;
  final String? asset;
}

class TypingSoundSettings {
  const TypingSoundSettings({
    this.preset = TypingSoundPreset.off,
    this.volume = .3,
  });
  final TypingSoundPreset preset;
  final double volume;
  TypingSoundSettings copyWith({TypingSoundPreset? preset, double? volume}) =>
      TypingSoundSettings(
        preset: preset ?? this.preset,
        volume: volume ?? this.volume,
      );
  Map<String, Object> toJson() => {'preset': preset.name, 'volume': volume};
  static TypingSoundSettings fromJson(Map<String, dynamic> json) =>
      TypingSoundSettings(
        preset:
            TypingSoundPreset.values
                .where((p) => p.name == json['preset'])
                .firstOrNull ??
            TypingSoundPreset.off,
        volume: ((json['volume'] as num?)?.toDouble() ?? .3).clamp(0, 1),
      );
}
