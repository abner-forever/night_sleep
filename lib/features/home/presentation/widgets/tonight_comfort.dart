import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_basics.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/quiet_surface.dart';
import '../../domain/sleep_comfort.dart';
import '../../domain/weather_snapshot.dart';

/// 首页那张「今晚怎么睡」。
///
/// 它是天气的**下游**：没有天气就不出现，不画占位、不写「暂无建议」。理由和
/// 天气卡一致——应用没有的东西就显示为没有，而不是拿一句空话占住一屏。
///
/// 卡片本身只放结论和三行动作，解释放在弹层里：首页是扫一眼的地方，
/// 「为什么是 26°」属于点进去才看的内容。
class TonightComfortCard extends StatelessWidget {
  const TonightComfortCard({
    super.key,
    required this.weather,
    required this.actionLabel,
    required this.onAction,
  });

  final WeatherSnapshot weather;

  /// 详情底部那颗按钮的文案。有会话在跑时不是「开始入睡」，而是回到会话。
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final advice = _adviceFor(weather);

    return Pressable(
      key: const ValueKey('home-comfort'),
      onTap: () => showTonightComfortSheet(
        context,
        weather: weather,
        actionLabel: actionLabel,
        onAction: onAction,
      ),
      semanticLabel: '今晚怎么睡，${advice.headline}，查看建议',
      child: QuietSurface(
        padding: const EdgeInsets.fromLTRB(16, 13, 13, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppIcons.moon(size: 15, color: tokens.accent),
                const SizedBox(width: 7),
                Text(
                  '今晚怎么睡',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    color: tokens.textMuted,
                  ),
                ),
                const Spacer(),
                Text(
                  '夜里最低 ${advice.nightLow}°',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: tokens.textMuted,
                    fontFeatures: AppTheme.tabular,
                  ),
                ),
                const SizedBox(width: 4),
                AppIcons.chevronRight(size: 14, color: tokens.textMuted),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              advice.headline,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.3,
                letterSpacing: -0.2,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 11),
            for (final (index, tip) in advice.tips.indexed) ...[
              if (index > 0) const SizedBox(height: 7),
              _ComfortRow(tip: tip),
            ],
          ],
        ),
      ),
    );
  }
}

/// 首页卡片里的一行：话题 + 短结论。
class _ComfortRow extends StatelessWidget {
  const _ComfortRow({required this.tip});

  final ComfortTip tip;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _iconFor(tip.topic, size: 14, color: tokens.accent),
        const SizedBox(width: 8),
        SizedBox(
          width: 28,
          child: Text(
            _label(tip.topic),
            style: TextStyle(fontSize: 10, color: tokens.textMuted),
          ),
        ),
        Expanded(
          child: Text(
            tip.action,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: tokens.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// 展开后的建议。每条都带「依据 + 做法」，末尾如实说明这是城市级预报。
class TonightComfortSheet extends StatelessWidget {
  const TonightComfortSheet({
    super.key,
    required this.weather,
    required this.actionLabel,
    required this.onAction,
  });

  final WeatherSnapshot weather;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final advice = _adviceFor(weather);

    return AppSheet(
      scrollable: true,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '今晚怎么睡',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
              color: tokens.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${weather.city} · ${weather.weatherText} · ${advice.basis}',
            style:
                TextStyle(fontSize: 11, height: 1.5, color: tokens.textMuted),
          ),
          const SizedBox(height: 16),
          QuietSurface(
            tint: tokens.bgMuted,
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            child: Text(
              advice.headline,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: tokens.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          for (final tip in advice.tips)
            _TipBlock(topic: tip.topic, action: tip.action, reason: tip.reason),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: AppIcons.sun(size: 14, color: tokens.caution),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  SleepComfortAdvice.target,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                    color: tokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            advice.humidityKnown
                ? '建议按城市级天气推算，卧室实际温湿度可能不同；身体感觉优先。'
                : '这次天气没有湿度数据，以上只按温度给出；卧室实际温湿度可能不同，身体感觉优先。',
            style:
                TextStyle(fontSize: 10, height: 1.6, color: tokens.textMuted),
          ),
          const SizedBox(height: 18),
          Pressable(
            key: const ValueKey('comfort-start-sleep'),
            onTap: () {
              Navigator.of(context).pop();
              onAction();
            },
            semanticLabel: actionLabel,
            child: Container(
              constraints: const BoxConstraints(minHeight: 50),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tokens.primaryActionFill,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppIcons.bed(size: 18, color: Colors.white),
                  const SizedBox(width: 7),
                  Text(
                    actionLabel,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 详情里的一条：图标 + 结论 + 依据。
class _TipBlock extends StatelessWidget {
  const _TipBlock({
    required this.topic,
    required this.action,
    required this.reason,
  });

  final ComfortTopic topic;
  final String action;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tokens.accentSoft,
            ),
            child: Center(
              child: _iconFor(topic, size: 17, color: tokens.accent),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_label(topic)} · $action',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  reason,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.65,
                    color: tokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 打开「今晚怎么睡」详情。
Future<void> showTonightComfortSheet(
  BuildContext context, {
  required WeatherSnapshot weather,
  required String actionLabel,
  required VoidCallback onAction,
}) {
  return showAppSheet<void>(
    context: context,
    builder: (context) => TonightComfortSheet(
      weather: weather,
      actionLabel: actionLabel,
      onAction: onAction,
    ),
  );
}

SleepComfortAdvice _adviceFor(WeatherSnapshot weather) => buildSleepComfort(
      temperature: weather.temperature,
      temperatureMin: weather.temperatureMin,
      windSpeed: weather.windspeed,
      weatherCode: weather.weatherCode,
      humidity: weather.humidity,
      precipitation: weather.precipitation,
    );

String _label(ComfortTopic topic) => switch (topic) {
      ComfortTopic.bedding => '被子',
      ComfortTopic.airConditioner => '空调',
      ComfortTopic.air => '空气',
    };

/// 三个话题复用 `AppIcons` 已有的图形：被子用床、空调用风扇、湿度用那滴水。
/// 不新增 SVG——图标生成物只通过 `tool/generate_app_icons.dart` 更新。
Widget _iconFor(
  ComfortTopic topic, {
  required double size,
  required Color color,
}) =>
    switch (topic) {
      ComfortTopic.bedding =>
        AppIcons.bed(size: size, color: color, strokeWidth: 1.7),
      ComfortTopic.airConditioner =>
        AppIcons.fan(size: size, color: color, strokeWidth: 1.7),
      ComfortTopic.air =>
        AppIcons.stream(size: size, color: color, strokeWidth: 1.7),
    };
