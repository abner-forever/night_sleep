import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../../core/widgets/subpage.dart';

/// 罗盘使用说明（二级页）。
///
/// 按盘面从外到内讲：先取平，再定针，然后读顶部金箭头下的度数，
/// 最后是二十四山与后天八卦的古法读法。**不编流派、不判吉凶**；
/// 古法部分只写通行整理，不冒充古籍原文。
class CompassManualPage extends StatelessWidget {
  const CompassManualPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Subpage(
      title: '罗盘使用说明',
      children: [
        Text(
          '先取平，再定针，最后读顶部金箭头下的度数。',
          style: TextStyle(fontSize: 13, height: 1.6, color: tokens.textMuted),
        ),
        const SizedBox(height: 14),
        _ManualCard(
          tokens: tokens,
          title: '一、怎么拿盘',
          children: [
            _body(
              tokens,
              '双手平托，或放在平稳的桌面上。先看罗盘正中的圆形水准器：'
              '气泡进入靶圈（总倾角不超过 1.5°）再读数。',
            ),
            _body(
              tokens,
              '读数不稳时，先远离金属、电器、磁吸壳、音箱等磁性物体（至少 1–1.5 米）。'
              '手机自身的振动马达、扬声器和保护壳也会影响磁力计。',
            ),
            _body(tokens, '同一位置测 2–3 次，取稳定后的读数。'),
          ],
        ),
        _ManualCard(
          tokens: tokens,
          title: '二、天池：针怎么指',
          children: [
            _body(
              tokens,
              '中央的磁针红头指磁北、白尾指南。池底那条红线是「海底线」，'
              '红头与它重合，就是用针定住了子午（子＝北，午＝南）。'
              '本页让盘面自动跟着方位转，所以磁针始终压在海底线上，不需要你手动转盘。',
            ),
            _body(
              tokens,
              '顶部的金色三角箭头是读线。手机屏幕的上沿就是你的朝向：'
              '金箭头落在盘面哪一格，你就在哪个方位。',
            ),
          ],
        ),
        _ManualCard(
          tokens: tokens,
          title: '三、怎么看针的指向（读盘）',
          children: [
            _body(
              tokens,
              '看三样东西，从上往下：顶部金箭头 → 紧贴刻度的二十四山与度数 → '
              '下方的大数字（精确到 1°）与山名。',
            ),
            _body(
              tokens,
              '盘面由外到内：最外是刻度（每 3° 一格，45° 一根长刻度并标度数）；'
              '紧贴刻度的是二十四山（每山 15°），再往里是后天八卦。',
            ),
            _example(tokens, '面向北', '金箭头对「0° · 子山」', '正北'),
            _example(tokens, '面向东', '金箭头对「90° · 卯山」', '正东'),
            _example(tokens, '面向南', '金箭头对「180° · 午山」', '正南'),
            _example(tokens, '面向西', '金箭头对「270° · 酉山」', '正西'),
            _body(
              tokens,
              '以「面向东」为例：此时北在你左手边，磁针红头会指向屏幕左侧，'
              '顶部金箭头对着「90° · 卯山」——红针指北、金箭头指你，两者不是同一个方向。',
            ),
          ],
        ),
        _ManualCard(
          tokens: tokens,
          title: '四、盘面从外到内',
          children: [
            _body(
              tokens,
              '① 外圈：度数（每 45° 标一个）与刻度（每 3° 一格）。'
              '② 二十四山：每山 15°，紧贴刻度。'
              '③ 后天八卦：每卦 45°，三山一卦。'
              '④ 天池：红白磁针、海底线、顶针。'
              '⑤ 中央：水平仪。',
            ),
            _body(
              tokens,
              '后天八卦的方位是：坎北、艮东北、震东、巽东南、'
              '离南、坤西南、兑西、乾西北。',
            ),
            const SizedBox(height: 6),
            _MountainTable(tokens: tokens),
          ],
        ),
        _ManualCard(
          tokens: tokens,
          title: '五、古人怎么记方位',
          children: [
            _body(
              tokens,
              '古法不先说「东南西北」，而是用二十四山：周天 360° 分成 24 份，'
              '每山 15°。二十四山由十二地支、八个天干和四个维卦组成。',
            ),
            _body(
              tokens,
              '十二地支：子丑寅卯辰巳午未申酉戌亥。'
              '八天干：甲乙丙丁庚辛壬癸（戊己居中央，不入盘）。'
              '四维：乾坤艮巽。四正为子午卯酉，四隅为乾坤艮巽。',
            ),
            _body(
              tokens,
              '三山一卦：壬子癸属坎、丑艮寅属艮、甲卯乙属震、辰巽巳属巽、'
              '丙午丁属离、未坤申属坤、庚酉辛属兑、戌乾亥属乾。'
              '读古书里的「某山某向」，就是先看朝向落在哪一山，再找对应的卦。',
            ),
            _body(
              tokens,
              '古书常记「坐某山、朝某向」：坐山与朝向相差 180°。'
              '本页只报你面对的方向（向），不推坐山，也不判吉凶。',
            ),
            _body(
              tokens,
              '本页只有地盘正针（子山 0°）。通行说法里，天盘「缝针」右移 7.5°、'
              '人盘「中针」左移 7.5°，本页没有做这两盘。'
              '清代王道亨《罗经透解》系统记载了多层罗盘；本页只取其结构'
              '（天池、内盘、外盘、天心十道），不作原文引用。',
            ),
          ],
        ),
        _ManualCard(
          tokens: tokens,
          title: '六、校准与边界',
          children: [
            _body(
              tokens,
              '状态行绿点表示磁场与校准正常；黄点或「请远离磁性物体，缓慢画「8」字校准」'
              '表示需要校准。把手机在空中缓慢画「8」字，等指针稳定再读。',
            ),
            _body(
              tokens,
              '方位无效时显示「—°」，不会编一个数给你。',
            ),
            _body(
              tokens,
              '本页显示磁北，不是地理北（没有磁偏角修正）。'
              '手机罗盘会受设备自身磁场影响，需要精确测量请用实体罗盘。',
            ),
            _body(
              tokens,
              '本页不保存任何数据，不写入睡眠记录，也不判断风水吉凶。',
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  static Widget _body(AppTokens tokens, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            height: 1.7,
            color: tokens.textSecondary,
          ),
        ),
      );

  static Widget _example(
          AppTokens tokens, String when, String where, String meaning) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 6),
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: tokens.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$when：',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        fontWeight: FontWeight.w600,
                        color: tokens.textPrimary,
                      ),
                    ),
                    TextSpan(
                      text: '$where → $meaning。',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        color: tokens.textSecondary,
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

class _ManualCard extends StatelessWidget {
  const _ManualCard({
    required this.tokens,
    required this.title,
    required this.children,
  });

  final AppTokens tokens;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: GlassSurface(
          borderRadius: BorderRadius.circular(AppRadii.card),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      );
}

/// 八宫二十四山的度数速查表。
///
/// 表比整段文字更好用：读到「艮」时能立刻知道它在 45°，
/// 也知道它和丑、寅同属一卦。
class _MountainTable extends StatelessWidget {
  const _MountainTable({required this.tokens});

  final AppTokens tokens;

  static const _rows = <(String, String)>[
    ('坎', '壬 345° · 子 0° · 癸 15°'),
    ('艮', '丑 30° · 艮 45° · 寅 60°'),
    ('震', '甲 75° · 卯 90° · 乙 105°'),
    ('巽', '辰 120° · 巽 135° · 巳 150°'),
    ('离', '丙 165° · 午 180° · 丁 195°'),
    ('坤', '未 210° · 坤 225° · 申 240°'),
    ('兑', '庚 255° · 酉 270° · 辛 285°'),
    ('乾', '戌 300° · 乾 315° · 亥 330°'),
  ];

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: tokens.bgMuted,
          borderRadius: BorderRadius.circular(AppRadii.panel),
        ),
        child: Column(
          children: [
            for (var index = 0; index < _rows.length; index++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text(
                        _rows[index].$1,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: tokens.accent,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _rows[index].$2,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: tokens.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (index != _rows.length - 1)
                Container(height: 1, color: tokens.border),
            ],
          ],
        ),
      );
}
