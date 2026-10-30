# MoonRTSP 选题与有界查重记录

检索与预留日期：2026-10-30。方向经使用者确认。本记录说明可访问资料中的比较结果，不构成绝对唯一性或比赛通过保证。

## 候选与需求

| 候选领域 | 成熟依据 | 发现与结论 |
| --- | --- | --- |
| 模板渲染 | Liquid/Jinja | MoonCakes 已有同领域项目，直接重合，淘汰 |
| 数据序列化 | Apache Avro | 已有 Avro 实现，直接重合，淘汰 |
| 构建工具 | Ninja | 已有构建实现，直接重合，淘汰 |
| 流媒体会话客户端 | RFC 2326、gortsplib、MediaMTX | 现有 RTP/SDP 原语缺少可直接使用的 RTSP 会话、播放与发布链路，进入实现 |

针对 RTSP，生态广度、用户多样性、复用、重合风险、深度、可验证性、工期和维护分别评为 4/4/4/4/5/5/3/3（1–5，重合风险得分高表示风险较低）。这些是工程判断，并非用户访谈或主办方评分。其它候选已在直接重合门禁淘汰，不以总分抵消。

实际需求依据是 RTSP 标准和成熟服务的现有接口：运维者读取媒体描述，摄像机接入程序选择轨道并收包，媒体生成程序将已编码 RTP 发布到流媒体服务。交付必须完成这些网络任务，不能仅提供文本编解码。

## 检索范围与结果

MoonCakes 使用较大上限 `moon search <keyword> --limit 100`，包括 rtsp、rtsps、rfc2326、rfc7826、gortsplib、live555、rtp、rtcp、sdp、h264，以及模板、序列化和构建候选词。rtsp、rfc7826、gortsplib、live555 未命中直接实现；rtsps 的模糊结果为 ROS2/RTC，rfc2326 命中 SDP 相邻项。零命中仅是线索。

GitHub 仓库搜索 `RTSP MoonBit` 返回 total_count=0、incomplete_results=false；读取官方 moonbitlang/awesome-moonbit 清单及候选上游 Git tree，检查源码、接口与测试。共享注册表读取 MoonWire、MoonRFB、MoonOSC 等完整相关指纹，随后在排他锁内预留本方向。公共记录不包含其他任务的私有文件路径或身份凭据。

## 语义比较

| 项目 | 输入、模型与行为 | 用户工作流与接口 | 分类及处理 |
| --- | --- | --- | --- |
| moonbit-community/rtc.mbt 0.0.1 | RTP/RTCP、WebRTC 原语和媒体载荷 | WebRTC/媒体开发者调用包接口 | 高度相邻，但没有 RTSP 控制会话；直接依赖 RTP、RTCP 和载荷实现，不复制其功能 |
| coke089/moon-sdp 0.1.0 | SDP 文档、属性与媒体段 | 离线解析/生成会话描述 | 同方向不同功能；依赖它解析 SDP，新增 RTSP Content-Base/control/轨道选择 |
| MoonWire（注册表 rejected） | 通用协议 framing | 离线框架演示 | 核心任务不同；本项目必须交付真实 socket 播放和发布，否则不满足选题 |
| MoonRFB | VNC framebuffer 协议 | 远程桌面客户端 | 无实质重合 |
| MoonOSC | Open Sound Control 消息 | 控制消息网络通信 | 无实质重合 |
| bluenviron/gortsplib | RTSP 客户端与服务端、多种安全和媒体扩展 | Go 生产流媒体系统 | 跨生态成熟参考，不声明全量移植或完整等价 |
| bluenviron/mediamtx | 多协议媒体服务 | 摄像机与播放器接入 | 独立互操作服务；未将其实现计入 MoonBit 生产代码 |

源码复核定位：rtc.mbt `rtp/packet.mbt` 与测试；moon-sdp `src/model.mbt`、parser 与测试；gortsplib `pkg/auth/sender.go`、认证测试与 `client_play_test.go`。研究时源树分别为 rtc 48bb728f1ce3563f2a859113dca53d949ef2c00d、moon-sdp 5d966d9dc486ea6b0ff3872571c67eff9e86ff6e、gortsplib 943f5ac38a8e99b79554640c1243073c82125b67。

## 核心指纹与完成标准

输入：无嵌入凭据 RTSP URL、独立凭据、轨道选择、SDP 和 RTP/RTCP。核心行为：CSeq/Session 状态管理、认证重试、TCP 交织/UDP 协商、PLAY/PAUSE/ANNOUNCE/RECORD/keepalive、超时取消、重连和媒体分发。输出：类型化轨道、媒体事件、统计与有界帧。API 包与 CLI 可独立复用。

完成标准是独立服务上的多轨认证发布、TCP/UDP 播放、暂停恢复与保活，以及错误/取消/重连测试。完整服务器、TLS/SRTP、ONVIF、WebRTC、解码显示、组播与隧道不在范围。源代码规模和提交数不能替代上述任务。

## 资料入口与限制

- https://github.com/moonbitlang/awesome-moonbit
- https://github.com/moonbit-community/rtc.mbt
- https://github.com/coke089/moon-sdp
- https://github.com/bluenviron/gortsplib
- https://github.com/bluenviron/mediamtx
- https://www.rfc-editor.org/rfc/rfc2326

搜索依赖当时公开可访问的索引、命名与仓库内容，不能排除未发布、私有或尚未被索引的项目。在记录范围内未发现成熟的 MoonBit RTSP 客户端直接替代。最终复核的实际结果记录如下。

最终发布前复核（2026-10-30）：MoonCakes 的 rtsp/gortsplib/live555/rfc7826 四项均返回空结果；GitHub rtsp+language:MoonBit 为 total_count=0、incomplete_results=false；共享注册表重新扫描 RTSP，仅本项目预留项。同名 GitHub 仓库与 MoonCakes 精确版本创建前均为官方 404。结论仍限于可访问和已索引内容。
