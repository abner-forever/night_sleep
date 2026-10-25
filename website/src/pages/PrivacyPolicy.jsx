import { useEffect } from 'react'
import { useSearchParams } from 'react-router-dom'
import './PrivacyPolicy.css'

const contactEmail = '1661287843@qq.com'

export default function PrivacyPolicy() {
  const [params] = useSearchParams()
  const embedded = params.get('app') === '1'
  const theme = params.get('theme') === 'dark' ? 'dark' : 'light'

  // 官网滚动条是全局样式（index.css），画在 <html> 上，取不到页面外层那层
  // data-theme；这里把「内嵌 + App 主题」标到 <html>，供 PrivacyPolicy.css
  // 把滚动条颜色钉成 App 的深浅，不影响官网自身的主题属性。
  useEffect(() => {
    if (!embedded) return
    const root = document.documentElement
    root.dataset.page = 'privacy-embedded'
    root.dataset.pageTheme = theme
    return () => {
      delete root.dataset.page
      delete root.dataset.pageTheme
    }
  }, [embedded, theme])

  return (
    <div className={`privacy-policy${embedded ? ' privacy-policy--embedded' : ''}`} data-theme={embedded ? theme : undefined} lang="zh-CN">
      <article className="privacy-policy__document" aria-labelledby="privacy-title">
        <header className="privacy-policy__header">
          <p className="privacy-policy__eyebrow">夜深 · 数据与隐私</p>
          <h1 id="privacy-title">隐私协议</h1>
          <p className="privacy-policy__date">更新日期：2026 年 10 月 25 日<br />生效日期：2026 年 10 月 25 日</p>
          <p>「夜深」是一款本地优先的睡眠记录应用，由个人开发者（项目账号：abner-forever，以下简称“我们”）开发与维护。本协议适用于夜深 App 及其官方网站，说明我们如何处理信息，以及你如何管理自己的数据。</p>
          <p>隐私联系邮箱：<a href={`mailto:${contactEmail}`}>{contactEmail}</a>。</p>
        </header>

        <aside className="privacy-policy__summary" aria-label="重点提示">
          <strong>请先了解这几件事</strong>
          <ul>
            <li>无需注册账号。睡眠记录和夜间录音默认保存在你的设备中，不上传至开发者服务器。</li>
            <li>夜间录音与联网洞察均为可选功能。<strong>睡眠健康信息和可能包含人声的录音涉及敏感个人信息，请谨慎启用及分享。</strong></li>
            <li>只有你主动生成联网洞察时，所选服务商才会收到该晚的结构化睡眠字段；录音文件和自由文本备注不发送。</li>
            <li>首页天气信息需要联网。未指定城市时，天气服务会使用请求 IP 解析城市级大致位置，不读取 GPS；不会发送睡眠记录或录音。</li>
            <li>检查版本、下载更新和打开官网页面会访问 GitHub 服务，对方会接收正常网络连接所需的信息。</li>
          </ul>
        </aside>

        <section aria-labelledby="privacy-local">
          <h2 id="privacy-local">一、我们处理哪些信息</h2>
          <h3>1. 睡眠记录与设置</h3>
          <p>当你记录、补录或编辑睡眠时，App 在本机保存入睡和起床时间、时区、时长、主观评分、备注、标签、你标记的打鼾或梦话等事件，以及记录来源。存在实际睡眠阶段数据时，会保存相应阶段与时段。进行中的睡眠会话、睡眠目标、提醒时间、主题、音效等偏好也保存在本机，用于继续记录、展示统计和恢复设置。</p>
          <p>当前版本没有接通健康平台或手环的数据导入，不会读取这些平台的健康数据，也不会凭空生成睡眠阶段。</p>
          <h3>2. 夜间录音与本机分析</h3>
          <p>仅在你开启夜间录音并授予麦克风权限后，App 才会在睡眠会话中录制环境声音。录音文件、发生时间、时长、波形、声音类别和分析结果保存在本机；声音判定模型随应用提供，在设备内运行，不将录音上传给我们或洞察服务商。</p>
          <p><strong>录音可能包含你或身边其他人的谈话等私密内容。请在合适的环境使用，并事先告知可能被录到的人、取得必要授权。不开启录音或拒绝麦克风权限，不影响手动记录睡眠。</strong></p>
          <h3>3. 罗盘与设备时区</h3>
          <p>打开罗盘时，App 使用设备支持的方向、磁场和运动传感器信息，在本机显示方位与姿态，不读取 GPS 定位，也不上传传感器读数。App 读取系统时区用于正确显示时间、安排本地提醒。</p>
          <h3>4. 天气信息</h3>
          <p>启用首页天气展示时，App 会向夜深天气服务发送网络请求。未指定城市时，服务端使用请求 IP 查询城市级大致位置，再向天气数据服务请求当前天气；不会读取设备 GPS 定位，也不会发送睡眠记录、录音或 API Key。若配置了城市名称，则请求可只携带该城市名称而不使用 IP 定位。</p>
          <p>天气结果包含城市、当前与最高/最低温度、天气类别、图标和风力等公开天气信息。天气服务不可用时，App 会显示“天气暂不可用”，不会使用占位温度冒充真实天气。</p>
          <h3>5. 联网洞察与 API Key</h3>
          <p>联网洞察由你自行选择服务商、填写自己的 API Key 后使用。App 使用系统安全存储机制保存密钥（iOS Keychain / Android 安全存储），在请求头中发送给你选定的服务商用于身份验证；不将密钥写入睡眠数据库、数据导出文件或应用日志。</p>
          <p>获取可用模型会发送认证信息；连通性测试还会发送模型名称和固定测试文本“ping”；余额查询会请求服务商账户余额信息。这些操作不会发送你的睡眠记录。</p>
          <p><strong>当你点击生成某晚的联网洞察时，App 会向选定服务商发送该晚的日期、入睡与起床时间、睡眠时长、主观质量；存在相应内容时，还包括你标记的不适事件、睡眠阶段占比、声音事件数量与分类汇总，以及模型名称和生成指令。不会发送自由文本备注、音频、波形文件或其他夜晚的完整记录。</strong>服务商返回的总结、评分、服务商及模型名称和生成时间保存在本机。</p>
          <p><strong>联网洞察会使上述健康相关信息离开设备。服务商可能在境外处理数据，其处理地域、留存及使用规则以该服务商当时适用的政策和你的账户约定为准。若你不希望数据发送至第三方，请不要使用该功能；本地记录与统计仍可使用。</strong>我们不提供医疗诊断，自动分析结果仅供日常记录参考。</p>
          <h3>6. 应用更新与网页访问</h3>
          <p>Android 设置页面展示版本信息时会检查一次公开版本，你也可以点击版本号主动检查。检查与下载通过 GitHub API、GitHub Releases 及其下载服务完成；App 在本机比较版本、校验安装包并交给系统安装。不会向 GitHub 发送睡眠记录、录音或 API Key，也不会未经你操作自动安装更新。</p>
          <p>在 App 中查看本协议会通过系统 WebView 加载官网。访问官网、查询版本、下载文件或打开第三方链接时，网络服务提供方会接收 IP 地址、请求时间、请求地址、浏览器或客户端类型等连接信息，并可能按照其政策保留访问日志。官网由 GitHub Pages 托管。</p>
          <h3>7. 你主动联系我们</h3>
          <p>当你通过邮箱或 GitHub 反馈问题时，我们会收到你主动发送的邮箱地址、账号、反馈内容和附件，仅用于答复、排查问题和处理隐私请求。请勿发送 API Key、完整录音或不必要的健康记录；如确需提供示例，请先去除个人信息。</p>
        </section>

        <section aria-labelledby="privacy-permissions">
          <h2 id="privacy-permissions">二、设备权限与系统能力</h2>
          <ul>
            <li><strong>麦克风：</strong>开启夜间录音时申请，用于录制环境声音。Android 使用麦克风前台服务及持续通知支持后台录音；iOS 使用系统允许的后台音频能力。你可关闭录音开关，或在系统设置中撤销权限。</li>
            <li><strong>通知：</strong>启用睡眠提醒等相关功能时申请，用于本地提醒及录音状态提示；不用于广告推送。拒绝通知可能影响提醒展示。</li>
            <li><strong>运动与方向传感器：</strong>用于罗盘的方位和姿态显示；若系统要求相应授权，你可拒绝，届时相关显示可能不可用。</li>
            <li><strong>安装应用（Android）：</strong>你确认更新时，系统可能要求允许本应用安装未知来源的安装包，仅用于交由系统安装本应用的更新。你可拒绝或在系统设置中撤销。</li>
            <li><strong>网络与开机恢复提醒：</strong>网络用于首页天气、可选洞察、版本检查、更新下载及打开网页；Android 接收系统开机事件以恢复你已设置的本地提醒。</li>
          </ul>
          <p>App 不申请通讯录、短信、相机或 GPS 定位权限，也不要求访问整个相册或全部共享文件来保存睡眠记录。拒绝可选权限只影响对应功能。</p>
        </section>

        <section aria-labelledby="privacy-third-parties">
          <h2 id="privacy-third-parties">三、第三方服务与信息共享</h2>
          <p>我们不出售个人信息，当前版本不集成广告、行为统计或第三方崩溃上报服务，也没有开发者运营的睡眠数据云端账户。除你选择的服务、主动分享或法律规定的情形外，不向第三方提供睡眠记录。</p>
          <ul>
            <li><strong>DeepSeek：</strong>你选择时用于模型列表、连通性测试、余额查询及联网洞察。接口域名：api.deepseek.com。<a href="https://cdn.deepseek.com/policies/zh-CN/deepseek-privacy-policy.html" rel="noreferrer">查看 DeepSeek 隐私政策</a>。</li>
            <li><strong>OpenAI：</strong>你选择时用于模型列表、连通性测试及联网洞察。接口域名：api.openai.com。<a href="https://openai.com/policies/privacy-policy/" rel="noreferrer">查看 OpenAI 隐私政策</a>。</li>
            <li><strong>Anthropic：</strong>当前版本仅支持使用你的认证信息获取模型列表，未接通其洞察生成与余额接口。接口域名：api.anthropic.com。<a href="https://www.anthropic.com/legal/privacy" rel="noreferrer">查看 Anthropic 隐私政策</a>。</li>
            <li><strong>GitHub：</strong>提供官网托管、公开版本查询、安装包下载及你主动使用的问题反馈。<a href="https://docs.github.com/zh/site-policy/privacy-policies/github-general-privacy-statement" rel="noreferrer">查看 GitHub 隐私声明</a>。</li>
            <li><strong>夜深天气服务：</strong>接收 App 的天气请求、请求 IP（用于城市级粗略定位）及可选城市名称，并返回当前天气。该服务由本项目维护，不接收睡眠记录、录音或 API Key。</li>
            <li><strong>和风天气（QWeather）：</strong>接收由夜深天气服务转发的城市级位置或坐标及请求时间，用于返回天气实况和预报。接口域名：qweather.com。天气服务不会把你的昼夜记录发送给和风天气。</li>
            <li><strong>ip-api.com：</strong>未指定城市时，夜深天气服务可能将请求 IP 发送给 ip-api.com，以获得城市级大致位置。该服务不接收 GPS 精度位置、睡眠记录或录音。接口域名：ip-api.com。</li>
            <li><strong>系统 WebView 与文件选择：</strong>WebView 仅用于显示网页，不注入睡眠数据、密钥或连接本地数据的 JavaScript 接口；导出与默认导入使用应用内设置的本地目录，手动导入时由系统文件选择器只返回你选中的文件。</li>
          </ul>
          <p>本地数据库、录音、音频播放、通知、安全存储和端侧模型等组件用于在设备上实现对应功能，不因使用这些组件而向其作者上传你的睡眠数据。第三方政策可能更新，请在使用前阅读；你可通过停止使用相应功能来停止后续发送。</p>
          <p>若未来涉及委托处理、转让或其他新增共享，我们会说明接收方、目的、信息类型和影响，并依法履行必要程序。依法必须披露时，我们仅提供必要范围内的信息。</p>
        </section>

        <section aria-labelledby="privacy-storage">
          <h2 id="privacy-storage">四、存储、安全与保留期限</h2>
          <p>睡眠记录、偏好和分析结果保存在设备的应用数据库，录音保存在应用私有目录。除你主动删除外，记录持续保留在本机。<strong>录音默认保留最近 7 晚，在应用执行清理时删除超期音频；对应的声音事件信息、波形与分类仍可能保留，直到你删除相关记录或执行删除全部录音／本地数据。</strong></p>
          <p>导出文件会写入默认目录或你授权给应用的本地目录，持续保留到你主动删除；生成过程中的临时副本和更新安装包位于应用缓存，可通过“清除缓存”清理或由系统回收。清除缓存不会删除已导出的文件、睡眠数据库或 API Key。官网及 WebView 可能保存网页资源缓存；官网还使用浏览器本地存储保存主题、语言和下载信息，下载信息正常缓存 5 分钟，网络异常时最多使用 24 小时内的有效缓存，不用于跨站广告跟踪。</p>
          <p>天气服务及上游天气、IP 城市解析服务可能为运行、安全和排障保留短期限访问日志，包括请求 IP、大致城市、请求时间和响应状态；日志不包含睡眠记录、录音或 API Key，并按服务运行需要定期清理。</p>
          <p>我们使用应用私有存储、系统安全存储、HTTPS 传输和更新包完整性校验等措施。睡眠数据库和录音并未额外实现应用级加密，请妥善设置设备锁屏，避免他人解锁访问、设备被破解或导出文件泄露。</p>
          <p>“本地保存”不等于排除操作系统备份：系统备份、设备迁移或钥匙串可能按你的系统设置保留、同步或恢复部分数据。卸载并不保证删除钥匙串、备份、已导出文件或第三方已收到的数据，你需要分别管理这些副本。</p>
          <p>你主动提交的反馈在处理和必要留存完成后删除或去标识化；你也可以通过联系邮箱申请删除。第三方服务接收的数据及其访问日志由对方按适用政策保留，我们无法代为直接删除。发生涉及你的个人信息安全事件时，我们会依法采取补救措施并履行通知等义务。</p>
        </section>

        <section aria-labelledby="privacy-rights">
          <h2 id="privacy-rights">五、你如何管理自己的信息</h2>
          <ul>
            <li><strong>查阅、更正：</strong>在睡眠记录、回顾和设置页面查看、修改已有记录及偏好。</li>
            <li><strong>导出：</strong>在“设置 → 睡眠数据管理”导出 CSV、JSON 或含录音的 ZIP。Android 10 及以上默认写入“下载/夜深”，Android 9 及以下写入应用文件目录，也可更换目录；iOS 默认写入“文件”App 内夜深目录的“导出”。导出文件可能包含备注或录音等私密信息，请妥善保管并在系统文件管理器中删除。</li>
            <li><strong>删除记录：</strong>删除单条睡眠记录，同时删除关联的阶段、声音事件、洞察及对应录音文件。</li>
            <li><strong>删除录音：</strong>在“设置 → 睡眠设置 → 删除全部录音”清理录音片段与对应声音事件；关闭夜间录音可停止后续录制。</li>
            <li><strong>删除本地数据：</strong>在“设置 → 删除全部本地数据”删除睡眠记录、阶段、声音事件、洞察、进行中的会话及相关录音。该操作保留偏好设置和安全存储中的 API Key；如需删除密钥，请在“睡眠洞察”设置中另行点击“清除密钥”。</li>
            <li><strong>撤回授权与停止发送：</strong>在系统设置关闭麦克风、通知等权限；停止使用联网洞察并清除 API Key，可停止后续向服务商发送请求。天气功能不申请 GPS 权限；如不希望请求携带网络 IP，可停止使用天气功能或在系统网络设置中限制本应用联网。撤回不会自动删除第三方已经收到的信息。</li>
            <li><strong>管理网页与外部副本：</strong>在浏览器或系统设置中管理网站存储、缓存和备份；在系统文件管理器中删除已导出的数据或撤回自定义目录授权。</li>
          </ul>
          <p>夜深没有注册账号，因此无需办理账号注销。我们无法远程读取、更正或恢复仅保存在你设备中的数据。若你需要行使查阅、复制、更正、删除、限制处理、撤回同意等适用权利，或对隐私处理有疑问、投诉，请发送邮件至 <a href={`mailto:${contactEmail}`}>{contactEmail}</a>；我们会在核实必要信息后尽快处理，通常在 15 个工作日内答复。核实时只会要求与请求有关的必要信息。</p>
        </section>

        <section aria-labelledby="privacy-children">
          <h2 id="privacy-children">六、未成年人保护</h2>
          <p>夜深不专门面向不满 14 周岁的儿童提供服务。未成年人应在监护人指导下使用；不满 14 周岁的儿童请勿自行启用录音、联网洞察或向我们提交个人信息。若监护人发现儿童信息被不适当处理，可联系我们协助处理或删除。若未来专门提供儿童服务，我们将另行制定规则并依法取得监护人同意。</p>
        </section>

        <section aria-labelledby="privacy-changes">
          <h2 id="privacy-changes">七、本协议的更新</h2>
          <p>我们会随功能变化或法律要求更新本协议，并在本页注明更新日期。若处理目的、信息种类、使用方式或接收方等发生重大变化，我们会通过 App 内提示等适当方式告知；依法需要同意或单独同意时，将在处理前另行征求。你可随时通过“设置 → 关于夜深 → 隐私协议”查看本页。</p>
        </section>

        <footer className="privacy-policy__contact">
          <h2>联系我们</h2>
          <p>个人开发者：abner-forever（夜深项目账号）<br />隐私联系邮箱：<a href={`mailto:${contactEmail}`}>{contactEmail}</a></p>
          <p>发送隐私请求时，请简要说明涉及的功能、希望处理的事项及可联系的方式。</p>
        </footer>
      </article>
    </div>
  )
}
