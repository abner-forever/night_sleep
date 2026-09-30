import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../domain/sleep_quality.dart';
import '../../domain/sleep_score.dart';
import '../../domain/sleep_stage.dart';
import '../../domain/sound_event.dart';

/// Maps domain enums onto the palette. Colour lives here rather than on the
/// enums so the domain layer stays free of Flutter types.
Color stageColor(AppTokens tokens, SleepStageType stage) => switch (stage) {
      SleepStageType.awake => tokens.stageAwake,
      SleepStageType.light => tokens.stageLight,
      SleepStageType.deep => tokens.stageDeep,
      SleepStageType.rem => tokens.stageRem,
    };

/// `durationColor` — one cue shared by bars, hero digits and record cards.
Color durationBandColor(AppTokens tokens, double hours) =>
    switch (durationBand(hours)) {
      DurationBand.healthy => tokens.accent,
      DurationBand.slightlyShort => tokens.caution,
      DurationBand.short => tokens.danger,
    };

/// `scoreColor` — one cue shared by rings and score labels.
Color scoreBandColor(AppTokens tokens, num score) => switch (scoreBand(score)) {
      ScoreBand.excellent => tokens.accentViolet,
      ScoreBand.good => tokens.accent,
      ScoreBand.fair => tokens.caution,
      ScoreBand.poor => tokens.danger,
    };

/// Accent used for each sound-event kind: snore reads blue, sleep talk violet.
Color soundEventColor(AppTokens tokens, SoundEventKind kind) => switch (kind) {
      SoundEventKind.snore => tokens.accentBlue,
      SoundEventKind.talk => tokens.accentViolet,
      SoundEventKind.noise => tokens.textMuted,
    };

/// `Q_LBL` 每一档的语义色。未评分（`null`）取中性色——那不是一个档位，
/// 不该借用任何一档的颜色。
Color qualityColor(AppTokens tokens, SleepQuality? quality) =>
    switch (quality) {
      null => tokens.textMuted,
      SleepQuality.veryPoor => tokens.danger,
      SleepQuality.poor => tokens.warn,
      SleepQuality.fair => tokens.caution,
      SleepQuality.good => tokens.accent,
      SleepQuality.excellent => tokens.accentViolet,
    };
