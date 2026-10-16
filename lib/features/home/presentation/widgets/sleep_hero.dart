import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/hero_surface.dart';
import '../../../sleep/domain/sleep_entry.dart';
import '../../../sleep/domain/sleep_stage.dart';
import '../../../sleep/presentation/sheets/detail_sheet.dart';
import '../../../sleep/presentation/widgets/moon_arc.dart';
import '../../../sleep/presentation/widgets/stage_chart.dart';
import '../../../sleep/presentation/widgets/stage_style.dart';
import '../../domain/home_insight.dart';

/// 首页那张夜色 hero 卡用的局部令牌（规格 §2.1）。
///
/// 照抄 [AppTokens.light]，只换下面这几个字段。**不写回 `AppTokens`**：与偏差 #32
/// 对会话页的裁定同源——这张卡整晚挂在夜色里，浅色主题下它也是深的，所以它自己
/// 带一套。约定不破：一个概念仍只有一处，只是这一处落在这一页。
///
/// 用法是 [HeroSurface.scopedTokens]：卡内每一个 `AppTokens.of(context)` 都读它。
///
/// **关于那 9 个字段**（规格那张表列的是前 8 个）：`bgMuted` 是实测补上的第 9 个。
/// 没有阶段数据那一支里，三个阶段格的底取的就是它，而那一格的文字取 `textMuted`
/// ——照抄浅色的 `#E9E9EF` 会得到「浅色字压在浅灰底上」，等于看不见。所以它跟着
/// 这张卡一起换成 `rgba(255,255,255,.07)`（与结论条同色）。
const _nightTokens = AppTokens(
  // ── 底色（照抄浅色；这张卡自己的底色走渐变，不用这几位） ──────────────────
  bgBase: Color(0xFFF2F2F7),
  bgCard: Color(0xB8FFFFFF),
  bgCardSolid: Color(0xFFFFFFFF),
  bgRaised: Color(0xA8FFFFFF),
  // 上面那条第 9 个：无阶段那三格 `—` 的底。
  bgMuted: Color(0x12FFFFFF),
  bgInput: Color(0x1F767680),
  bgNavbar: Color(0xC7F8F8FA),

  // ── 文字 ────────────────────────────────────────────────────────────────
  textPrimary: Color(0xFAFAFBFF), // rgba(250,251,255,.98)
  textSecondary: Color(0xC7E5EAFF), // rgba(229,234,255,.78)
  textMuted: Color(0x9EDAE2FF), // rgba(218,226,255,.62)

  // ── 强调色 ──────────────────────────────────────────────────────────────
  accent: Color(0xFF91C8FF),
  accentSoft: Color(0x2689BEFF), // rgba(137,190,255,.15)
  accentViolet: Color(0xFFB7A9FF),
  accentBlue: Color(0xFF5AC8FA),

  // ── 描边与材质 ──────────────────────────────────────────────────────────
  border: Color(0x21CFDCFF), // rgba(207,220,255,.13)
  borderStrong: Color(0x473C3C43),
  glassBorder: Color(0x24FFFFFF), // rgba(255,255,255,.14)
  sheetBg: Color(0xE0F9F9FB),
  specular: Color(0xB3FFFFFF),
  material: Color(0xA8FFFFFF),
  materialStrong: Color(0xDBFAFAFC),

  // ── 语义色 ──────────────────────────────────────────────────────────────
  danger: Color(0xFFE5484D),
  warn: Color(0xFFE08A3C),
  caution: Color(0xFFC8A93A),
  good: Color(0xFF2E9E83),

  // ── 阶段色 ──────────────────────────────────────────────────────────────
  stageDeep: Color(0xFF5856D6),
  stageLight: Color(0xFF5AC8FA),
  stageRem: Color(0xFFAF52DE),
  stageAwake: Color(0xFFFF3B30),

  // ── 多值 ────────────────────────────────────────────────────────────────
  atmosphere: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF6F8FF), Color(0xFFF2F2F7), Color(0xFFF2F2F7)],
    stops: [0.0, 0.42, 1.0],
  ),
  primaryActionGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0A84FF), Color(0xFF5856D6)],
  ),
  overlayScrim: Color(0x4D000000),
);

/// 首页的「昨夜睡眠」卡——夜色 hero（规格 §2.1）。
///
/// 三层底色叠在一张卡里：线性底 [LinearGradient]（卡自己画的）、右上那团**会呼吸**的
/// 月晕（[HeroGlow]，`breathe: true`），以及左下的青雾（`secondGlow`）。星点由
/// [HeroSurface.stars] 铺四个点。两团光晕都走 [HeroSurface] 那条绘制路径——
/// 那里是唯一一处会把它们裁进卡自己的圆角里的地方。
///
/// 内容顺序：头部行 → 睡眠盘 + 时长/评分/声音 + 入睡起床 → **结论条** → 阶段块。
/// 阶段块只在该记录确有阶段数据时出现（偏差 #10 的红线：不补、不猜）。
class SleepHeroCard extends StatelessWidget {
  const SleepHeroCard({
    super.key,
    required this.entry,
    required this.recentHours,
    required this.animateRing,
  });

  /// 昨夜那一条（`records.first`，最新在前）。
  final SleepEntry entry;

  /// 各晚时长（小时），**最新在前**——结论条那条差值吃它（规格 §4.1.1）。
  final List<double> recentHours;

  /// 首帧把睡眠盘从零画出来，沿用首页自己那份 `animateRing` 快照。
  final bool animateRing;

  @override
  Widget build(BuildContext context) {
    return HeroSurface(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF151D3C), Color(0xFF20204A), Color(0xFF102B3D)],
        stops: [0.0, 0.48, 1.0],
      ),
      // `0 18px 42px rgba(40,57,112,.24)`。原型另有一条 `inset 0 1px rgba(255,255,255,.16)`
      // 的顶边高光，Flutter 的 `BoxShadow` 没有 inset，改由卡内那条 1px 亮线近似
      // （见 [_NightHeroBody]）——阴影画在裁剪之外、又是画在卡**后面**的，
      // 拿一条 `offset: (0, 1)` 的阴影去凑只会落在卡的下缘。
      shadow: const [
        BoxShadow(
          color: Color(0x3D283970),
          blurRadius: 42,
          offset: Offset(0, 18),
        ),
      ],
      borderColor: const Color(0x24DAE4FF),
      borderRadius: BorderRadius.circular(AppRadii.card),
      padding: const EdgeInsets.all(20),
      // 右上月晕，`190×190` 放在 `top:-76 / right:-54`，5 秒一个来回。
      glow: const HeroGlow(
        size: 190,
        top: -76,
        right: -54,
        breathe: true,
        colors: [
          Color(0x47BDCFFF),
          Color(0x128091E5),
          Colors.transparent,
        ],
        stops: [0, 0.42, 0.70],
      ),
      // 左下青雾 `radial 80% 70% at 0% 100%`：原型是按卡的百分比给的一团椭圆，
      // 这里取一个同样贴住左下角、直径约卡宽 70% 的圆来近似。
      secondGlow: const HeroGlow(
        size: 250,
        left: -125,
        bottom: -125,
        colors: [Color(0x29389EAD), Colors.transparent],
        stops: [0, 0.68],
      ),
      stars: true,
      scopedTokens: _nightTokens,
      // 弹层挂在**卡外**那套令牌下。`showSleepDetailSheet` 走 `showAppSheet`，
      // 模态路由会把调用处的 `Theme` 一并捕获（`InheritedTheme.capture`）；
      // 这里用的是 [SleepHeroCard] 自己的 context——它在这张卡的 `Theme` **之上**，
      // 所以详情弹层拿到的仍是全局那套。卡内的 context 会把夜色令牌带进去。
      onTap: () => showSleepDetailSheet(context, entry),
      semanticLabel: '查看昨夜睡眠详情',
      child: _NightHeroBody(
        entry: entry,
        recentHours: recentHours,
        animateRing: animateRing,
      ),
    );
  }
}

/// hero 卡里的内容。
///
/// **它必须是 [HeroSurface] 的 `child`**，不能把这些令牌读取搬回 [SleepHeroCard.build]：
/// 局部令牌是 [HeroSurface] 在这棵子树**外面**套的一层 `Theme`，只有当 `context`
/// 落在那层 `Theme` 之下时，`AppTokens.of(context)` 才读得到它。
class _NightHeroBody extends StatelessWidget {
  const _NightHeroBody({
    required this.entry,
    required this.recentHours,
    required this.animateRing,
  });

  final SleepEntry entry;
  final List<double> recentHours;
  final bool animateRing;

  /// 内边距（卡自己的 `padding: EdgeInsets.all(20)`），那条顶边高光要反向越出它。
  static const _inset = 20.0;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final hours = entry.durationHours.floor();
    final minutes = ((entry.durationHours - hours) * 60).round();
    final score = entry.score;

    return Stack(
      // 顶边那条 1px 亮线画在这个盒子的**上方 20px 处**（也就是卡的上缘），
      // 越界绘制由外层 `ClipRRect` 收进卡自己的圆角里。
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(tokens),
            const SizedBox(height: 16),
            Row(
              children: [
                MoonArc(
                  durationHours: entry.durationHours,
                  stages: entry.stages,
                  size: 116,
                  animate: animateRing,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '$hours',
                            style: AppTheme.num(
                              context,
                              size: 42,
                              weight: FontWeight.w700,
                              letterSpacing: -1.26,
                            ),
                          ),
                          Text(
                            'h ',
                            style:
                                TextStyle(fontSize: 22, color: tokens.accent),
                          ),
                          Text(
                            '$minutes',
                            style: AppTheme.num(
                              context,
                              size: 42,
                              weight: FontWeight.w700,
                              letterSpacing: -1.26,
                            ),
                          ),
                          Text(
                            'm',
                            style:
                                TextStyle(fontSize: 22, color: tokens.accent),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (score != null)
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.accentSoft,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  AppIcons.ai(
                                    size: 11,
                                    color: tokens.accent,
                                    strokeWidth: 2,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$score分',
                                    style: AppTheme.num(
                                      context,
                                      size: 12,
                                      weight: FontWeight.w700,
                                      color: tokens.accent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                // 「全程安静」把「录过、没听到」与「根本没录」
                                // 说成同一件事，等于替用户下一个我们没有依据的
                                // 结论。零片段就只说零片段。
                                entry.hasSoundEvents
                                    ? '${entry.soundClips.length}条声音'
                                    : '无声音片段',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: tokens.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          AppIcons.bed(
                            size: 12,
                            color: tokens.accent,
                            strokeWidth: 1.8,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            entry.bedtimeLabel,
                            style: AppTheme.num(
                              context,
                              size: 12,
                              weight: FontWeight.w600,
                              color: tokens.accent,
                            ),
                          ),
                          Expanded(
                            child: Container(
                              height: 1,
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              color: tokens.border,
                            ),
                          ),
                          AppIcons.sun(
                            size: 12,
                            color: tokens.accentViolet,
                            strokeWidth: 1.8,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            entry.wakeLabel,
                            style: AppTheme.num(
                              context,
                              size: 12,
                              weight: FontWeight.w600,
                              color: tokens.accentViolet,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // 结论条。它只说时长这一件真的测过的事（规格 §4.1.1）。
            _InsightStrip(
              insight: durationInsightSentence(durationDelta(recentHours)),
              advice: durationAdviceSentence(entry.durationHours),
            ),
            if (entry.hasStages) ...[
              const SizedBox(height: 20),
              Divider(height: 1, color: tokens.border),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final stage in SleepStageType.charted)
                    Expanded(
                      child: _StageStat(
                        stage: stage,
                        value: _formatMinutes(entry.minutesFor(stage)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              StageBarChart(
                stages: entry.stages,
                height: 24,
                profile: StageBarProfile.hero,
                gap: 1,
              ),
              const SizedBox(height: 6),
              StageLegend(stages: entry.stages),
            ] else ...[
              // The prototype's card always shows this block, because every
              // record in it carries a hypnogram. A hand-logged night does
              // not, and putting numbers in the three tiles would be
              // presenting a distribution nobody measured. So the block keeps
              // the same shape and says what is missing, rather than
              // vanishing and leaving the card looking half-built.
              const SizedBox(height: 20),
              Divider(height: 1, color: tokens.border),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final stage in SleepStageType.charted)
                    Expanded(child: _StageStat(stage: stage, value: '—')),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppIcons.moon(
                    size: 13,
                    color: tokens.textMuted,
                    strokeWidth: 1.8,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '这一晚没有睡眠阶段数据。手写记录只有起止时间和主观质量；'
                      '深睡、浅睡、REM 要等设备测量或导入之后才会显示。',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: tokens.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        // `inset 0 1px rgba(255,255,255,.16)`：Flutter 没有 inset 阴影，用一条
        // 贴住卡上缘的 1px 亮线近似。反向越出内容的内边距才落得到卡边上，
        // 两侧同理；越界的部分由外层 `ClipRRect` 裁进圆角。
        //
        // 这条线归内容层（在星点与光晕**之上**）：原型那个 inset 也是画在
        // 卡片填充之后的，压在光晕上面的观感才是一道亮边。
        Positioned(
          top: -_inset,
          left: -_inset,
          right: -_inset,
          height: 1,
          child: IgnorePointer(
            child: ColoredBox(color: Colors.white.withValues(alpha: 0.16)),
          ),
        ),
      ],
    );
  }

  /// 头部行：月亮 + 「昨夜睡眠」+ 右侧 `详情 ›`。
  Widget _header(AppTokens tokens) => Row(
        children: [
          AppIcons.moon(size: 13, color: tokens.textMuted, strokeWidth: 1.8),
          const SizedBox(width: 6),
          Text(
            '昨夜睡眠',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.96,
              color: tokens.textMuted,
            ),
          ),
          const Spacer(),
          Text('详情', style: TextStyle(fontSize: 12, color: tokens.textMuted)),
          AppIcons.chevronRight(
            size: 14,
            color: tokens.textMuted,
            strokeWidth: 2,
          ),
        ],
      );
}

/// 结论条（规格 §4.1.1）：圆点 + 「与近 7 日平均比」一行 + 一句当晚就能做的事。
///
/// 它只说时长。不说「深睡表现不错」这类话——本应用没有可靠的阶段结论，
/// 而 `notes` 与事件都是用户自己填的。
class _InsightStrip extends StatelessWidget {
  const _InsightStrip({required this.insight, required this.advice});

  final String insight;
  final String advice;

  /// 圆点的颜色。
  ///
  /// 规格 §3.2 把 `#86D8C6` 标成**给深底用的**那个值（浅底上对比度不够，浅色取
  /// `#2E9E83`）。这张卡在浅色主题下也是深的，所以取它——而不是卡内令牌的
  /// `good`，那一位照抄的是浅色的 `#2E9E83`。
  static const _mark = Color(0xFF86D8C6);

  /// 圆点比第一行那 13px 的字矮 11px，往下推半个字高才落在它的中线上。
  static const _markTop = 5.0;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      // 规格写的是 `margin-top: 18`。
      padding: const EdgeInsets.only(top: 18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0x12FFFFFF), // rgba(255,255,255,.07)
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: const Color(0x17FFFFFF)), // rgba(255,255,255,.09)
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: _markTop),
              child: Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: _mark,
                  shape: BoxShape.circle,
                  // 两层光晕环：`0 0 0 5px rgba(134,216,198,.1)` 与
                  // `0 0 12px rgba(134,216,198,.42)`。
                  boxShadow: [
                    BoxShadow(color: Color(0x1A86D8C6), spreadRadius: 5),
                    BoxShadow(color: Color(0x6B86D8C6), blurRadius: 12),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    insight,
                    style: TextStyle(
                      fontSize: 13,
                      // 原型是 w650；`FontWeight` 只有整百档，取更接近的 w600。
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    advice,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.52),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the three stage totals under the hero dial.
class _StageStat extends StatelessWidget {
  const _StageStat({required this.stage, required this.value});

  final SleepStageType stage;

  /// A formatted duration, or an em dash when nothing was measured.
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final measured = value != '—';
    final color = stageColor(tokens, stage);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: measured ? color.withValues(alpha: 0.10) : tokens.bgMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stage.label,
            maxLines: 1,
            style: TextStyle(fontSize: 11, color: tokens.textMuted),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            style: AppTheme.num(
              context,
              size: 15,
              weight: FontWeight.w600,
              color: measured ? color : tokens.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatMinutes(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '${hours}h' : '${hours}h${rest}m';
}
