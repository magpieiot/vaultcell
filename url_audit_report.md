# URL 审计总结报告（apps_500_min.json）

- 条目总数：**500**
- 原始全部满足 4 项要求：**0 / 500**（原始均缺失 `https://`，故为 0）
- 原始即含 `https://`：**0 / 500**（500 条缺失协议头，需补）
- 原始带多余 path：**0** 条
- 因可达性需补 `www.`：**45** 条
- 清洗后 URL 发生改动：**46** 条
- 脚本无法验证可达性（本机 TLS 受限）：**43** 个 host（其中 域名解析失败 0、TLS 握手失败 42、连接/其他失败 1）。**注意**：其中多数为本机网络代理对部分站点 TLS 握手拦截所致（如 adobe.com、yizhibo.com、Notability/gingerlabs.com 等知名站点几乎必然可达，属误报），仅代表「脚本无法验证」，不代表站点真实不可达，需人工最终确认。
- 疑似非品牌官方站（占位/共用 CDN，建议人工核对）：**30** 条

## 一、清洗后 URL 发生改动的条目

| 名称 | 原 url | 清洗后 url | 改动原因 |
|---|---|---|---|
| 招商银行 | cmbchina.com | https://www.cmbchina.com | 补 https://, 补 www.(naked 不可达) |
| 中国农业银行 | abchina.com | https://www.abchina.com | 补 https://, 补 www.(naked 不可达) |
| 盒马 | freshhema.com | https://www.freshhema.com | 补 https://, 补 www.(naked 不可达) |
| 交管12123 | tmri.cn | https://www.tmri.cn | 补 https://, 补 www.(naked 不可达) |
| 掌上生活 | cmbchina.com | https://www.cmbchina.com | 补 https://, 补 www.(naked 不可达) |
| 安逸花 | msxf.com | https://www.msxf.com | 补 https://, 补 www.(naked 不可达) |
| Colorful Widget彩虹小组件 | colorfulwidget.com | https://www.colorfulwidget.com | 补 https://, 补 www.(naked 不可达) |
| 今日水印相机 | dddsway.com | https://www.dddsway.com | 补 https://, 补 www.(naked 不可达) |
| 肯德基KFC | kfc.com.cn | https://www.kfc.com.cn | 补 https://, 补 www.(naked 不可达) |
| 台球世界 | 52mvp.com | https://www.52mvp.com | 补 https://, 补 www.(naked 不可达) |
| 中国国航 | airchina.com.cn | https://www.airchina.com.cn | 补 https://, 补 www.(naked 不可达) |
| 口碑 | koubei.com | https://www.koubei.com | 补 https://, 补 www.(naked 不可达) |
| 儿歌多多 | ergeduoduo.com | https://www.ergeduoduo.com | 补 https://, 补 www.(naked 不可达) |
| 梦想城镇 | mygamez.cn | https://www.mygamez.cn | 补 https://, 补 www.(naked 不可达) |
| Microsoft Outlook | live.com | https://www.live.com | 补 https://, 补 www.(naked 不可达) |
| 邮储银行 | psbc.com | https://www.psbc.com | 补 https://, 补 www.(naked 不可达) |
| 全球购骑士特权 | black-unique.com | https://www.black-unique.com | 补 https://, 补 www.(naked 不可达) |
| 航旅纵横 | umetrip.com.cn | https://www.umetrip.com.cn | 补 https://, 补 www.(naked 不可达) |
| 兴业银行手机银行 | cib.com.cn | https://www.cib.com.cn | 补 https://, 补 www.(naked 不可达) |
| 七猫小说 | wtzw.com | https://www.wtzw.com | 补 https://, 补 www.(naked 不可达) |
| 浦发银行 | spdb.com.cn | https://www.spdb.com.cn | 补 https://, 补 www.(naked 不可达) |
| Prodrafts | emmo.club | https://www.emmo.club | 补 https://, 补 www.(naked 不可达) |
| IKEA 宜家家居 | ikea.cn | https://www.ikea.cn | 补 https://, 补 www.(naked 不可达) |
| Microsoft OneNote | OneNote.com | https://www.onenote.com | 补 https://, 补 www.(naked 不可达) |
| 多闪 | duoshanapp.com | https://www.duoshanapp.com | 补 https://, 补 www.(naked 不可达) |
| 个人所得税 | chinatax.gov.cn | https://www.chinatax.gov.cn | 补 https://, 补 www.(naked 不可达) |
| 浦大喜奔 | spdb.com.cn | https://www.spdb.com.cn | 补 https://, 补 www.(naked 不可达) |
| 细说心事 | tangchaolw.chat | https://www.tangchaolw.chat | 补 https://, 补 www.(naked 不可达) |
| 中国联通 | 10010.com | https://www.10010.com | 补 https://, 补 www.(naked 不可达) |
| 打印机 | airprinter.app | https://www.airprinter.app | 补 https://, 补 www.(naked 不可达) |
| 杭州市民卡App | 96225.com | https://www.96225.com | 补 https://, 补 www.(naked 不可达) |
| 拉卡拉 | lakala.com | https://www.lakala.com | 补 https://, 补 www.(naked 不可达) |
| 人教点读 | mypep.cn | https://www.mypep.cn | 补 https://, 补 www.(naked 不可达) |
| 翻译 | gamecultures.com | https://www.gamecultures.com | 补 https://, 补 www.(naked 不可达) |
| ProMovie 专业摄像机 | ProMovieApp.com | https://promovieapp.com | 补 https:// |
| 一汽奥迪 | faw-vw.com | https://www.faw-vw.com | 补 https://, 补 www.(naked 不可达) |
| 东方购物 | ocj.com.cn | https://www.ocj.com.cn | 补 https://, 补 www.(naked 不可达) |
| 阳光惠生活 | cebbank.com | https://www.cebbank.com | 补 https://, 补 www.(naked 不可达) |
| 大麦 | damai.cn | https://www.damai.cn | 补 https://, 补 www.(naked 不可达) |
| 最后一卷胶片 | yoodoo.tech | https://www.yoodoo.tech | 补 https://, 补 www.(naked 不可达) |
| 少年得到 | igetcool.com | https://www.igetcool.com | 补 https://, 补 www.(naked 不可达) |
| 英语天天练 | chuangjing.com | https://www.chuangjing.com | 补 https://, 补 www.(naked 不可达) |
| 中油好客e站 | cnpc.com.cn | https://www.cnpc.com.cn | 补 https://, 补 www.(naked 不可达) |
| 实习僧 | shixiseng.com | https://www.shixiseng.com | 补 https://, 补 www.(naked 不可达) |
| 兼职猫 | jianzhimao.com | https://www.jianzhimao.com | 补 https://, 补 www.(naked 不可达) |
| 丰收互联 | zj96596.com | https://www.zj96596.com | 补 https://, 补 www.(naked 不可达) |

## 二、脚本无法验证可达性的域名（本机 TLS 限制，建议人工确认）

> 说明：下表 host 在脚本探测中 TLS 握手失败或连接超时。多为本机代理/网络对部分站点 TLS 指纹不兼容（含 adobe.com、yizhibo.com、Notability 等明显可达的知名站点，属误报）。请人工用浏览器最终确认；若同时出现在第三节「疑似错误域名」，则优先按其建议替换为品牌官方站。

| 名称 | host | naked | www | 清洗后 url | 说明 |
|---|---|---|---|---|---|
| 轻颜 | bytecdn.com | ssl | ssl | https://bytecdn.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 钉钉 | alicdn.com | ssl | ssl | https://alicdn.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 淘宝 | alicdn.com | ssl | ssl | https://alicdn.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 天猫 | alicdn.com | ssl | ssl | https://alicdn.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 天气预报 | caochen.com | ssl | ssl | https://caochen.com | TLS协议错误(脚本无法验证,建议人工确认) |
| NOMO CAM | alicdn.com | ssl | ssl | https://alicdn.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 楼下的早餐店：美食烹饪游戏 | ccyiyo.com | ssl | ssl | https://ccyiyo.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 悟空浏览器 | draftstatic.com | ssl | ssl | https://draftstatic.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 懂车帝 | dcarapi.com | ssl | ssl | https://dcarapi.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 飞常准 | feeyo.com | other | ssl | https://feeyo.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 抖音来客 | draftstatic.com | ssl | ssl | https://draftstatic.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 黄历 | xdmobile.cn | ssl | ssl | https://xdmobile.cn | TLS协议错误(脚本无法验证,建议人工确认) |
| 洋码头 | yangmatou.com | ssl | ssl | https://yangmatou.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 豆包爱学 | draftstatic.com | ssl | ssl | https://draftstatic.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 中华日历 | xdmobile.cn | ssl | ssl | https://xdmobile.cn | TLS协议错误(脚本无法验证,建议人工确认) |
| 千问 | alicdn.com | ssl | ssl | https://alicdn.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 吾记 | xiejianji.com | ssl | ssl | https://xiejianji.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 图虫 | ituchong.com | ssl | ssl | https://ituchong.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 万年历纯净版 | bazixinli.com | ssl | ssl | https://bazixinli.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 怀孕管家 | huaiyuanguanjia.com | ssl | ssl | https://huaiyuanguanjia.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 出国翻译官 | qcmuzhi.com | ssl | ssl | https://qcmuzhi.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 抖音火山版 | draftstatic.com | ssl | ssl | https://draftstatic.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 国家反诈中心 | chanct.cn | ssl | ssl | https://chanct.cn | TLS协议错误(脚本无法验证,建议人工确认) |
| 鱼泡直聘 | ytmpw.com | ssl | ssl | https://ytmpw.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 心动小镇 | xd.cn | ssl | ssl | https://xd.cn | TLS协议错误(脚本无法验证,建议人工确认) |
| 全能扫描仪 | scannerapp.online | timeout | ssl | https://scannerapp.online | TLS协议错误(脚本无法验证,建议人工确认) |
| 喵街 | alicdn.com | ssl | ssl | https://alicdn.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 小鳄鱼Hay | cacheserv.com | ssl | ssl | https://cacheserv.com | TLS协议错误(脚本无法验证,建议人工确认) |
| Phigros | pigeongames.cn | ssl | ssl | https://pigeongames.cn | TLS协议错误(脚本无法验证,建议人工确认) |
| 抖音商城 | draftstatic.com | ssl | ssl | https://draftstatic.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 电视直播TV | xiaoyouzb.net | ssl | ssl | https://xiaoyouzb.net | TLS协议错误(脚本无法验证,建议人工确认) |
| 千牛 | alicdn.com | ssl | ssl | https://alicdn.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 一直播 | yizhibo.com | ssl | ssl | https://yizhibo.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 初音未来：缤纷舞台 | draftstatic.com | ssl | ssl | https://draftstatic.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 书旗小说 | alicdn.com | ssl | ssl | https://alicdn.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 小白学习打印 | xbxxhz.com | ssl | ssl | https://xbxxhz.com | TLS协议错误(脚本无法验证,建议人工确认) |
| Lightroom AI 照片视频编辑器・修图神器・修图软件 | adobe.com | other | other | https://adobe.com | 其他失败(建议人工确认) |
| 指尖天气预报 | haitunonline.com | ssl | ssl | https://haitunonline.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 熊猫起名 | xdmobile.cn | ssl | ssl | https://xdmobile.cn | TLS协议错误(脚本无法验证,建议人工确认) |
| 陕西社会保险 | pansky.com.cn | ssl | ssl | https://pansky.com.cn | TLS协议错误(脚本无法验证,建议人工确认) |
| 淘宝闪购商家版 | alicdn.com | ssl | ssl | https://alicdn.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 全民找茬 | shuidifarm.com | ssl | ssl | https://shuidifarm.com | TLS协议错误(脚本无法验证,建议人工确认) |
| 点淘 | alicdn.com | ssl | ssl | https://alicdn.com | TLS协议错误(脚本无法验证,建议人工确认) |

## 三、疑似错误域名（占位/共用 CDN，建议人工替换为品牌官方站）

| host | 出现次数 | 关联应用 | 建议替换 |
|---|---|---|---|
| alicdn.com | 10 | 钉钉、淘宝、天猫、NOMO CAM、千问、喵街、千牛、书旗小说… | 阿里巴巴系官网（淘宝 taobao.com / 天猫 tmall.com / 钉钉 dingtalk.com / 千牛 qianniu.com / 书旗 shuqi.com / 点淘 diantao.com 等），非 CDN 域名 |
| draftstatic.com | 6 | 悟空浏览器、抖音来客、豆包爱学、抖音火山版、抖音商城、初音未来：缤纷舞台 | 对应 App 官网（字节系静态 CDN，非官方站） |
| wikidata.org | 4 | 汽车之家、斗地主经典版、Apple 钱包、Hp Smart App | 各 App 官网（如 汽车之家 autohome.com），非维基数据站点 |
| github.io | 2 | 小日常、音乐剪辑 | 对应 <user>.github.io 或官网（裸 github.io 不是有效站点） |
| csdn.net | 2 | 233乐园、EMMO 日记 | 各 App 官网，非 CSDN 技术社区 |
| bytecdn.com | 1 | 轻颜 | 对应 App 官网（CDN 域名，非官方站） |
| blogspot.com | 1 | 沙威玛传奇 | 对应 App 官网（裸 blogspot.com 不是有效站点） |
| clouddn.com | 1 | 省钱快报 | 对应 App 官网（CDN 域名，非官方站） |
| bdstatic.com | 1 | 百度极速版 | baidu.com 或 shouji.baidu.com（百度静态资源 CDN，非官网） |
| lofter.com | 1 | 北斗导航 | 对应 App 官网（网易 Lofter 域名，非北斗官网） |
| tools-global.com | 1 | call录通话 | 对应 App 官网 |

## 四、说明

- **完整性(req1)**：清洗后所有 url 均以 `https://` 开头（原 500 条均无协议头）。
- **www.(req2)**：仅当 `https://host` 不可达而 `https://www.host` 可达时才补 `www.`；两者均可达时优先最简（不带 www）。
- **无多余 path(req3)**：原数据均仅为 host，无 path；清洗后仅保留 host。
- **可访问最简表达(req4)**：使用系统 `curl` 对 `https://host` 与 `https://www.host` 做实际探测（跟随重定向，只读状态码；探测时关闭证书校验以规避本机代理/MITM 对脚本客户端的拦截，仅用于判断主机是否响应）。状态码 2xx–5xx 视为可达。
- **可达性细分**：解析失败=域名大概率无效；TLS 握手失败/连接超时=脚本客户端受限（银行/旧站/CDN 常因 TLS 指纹或代理被拒），不代表用户浏览器不可访问，建议人工最终确认。
- 疑似错误域名仅作提示，**未自动改写**（避免误改品牌官方站）。清洗文件：`apps_500_min_fixed.json`；逐条明细：`url_audit_full.csv`。