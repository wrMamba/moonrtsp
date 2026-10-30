# 依据、依赖与能力对照

原创 MoonBit RTSP 客户端，按 RFC 2326 的 RTSP 1.0 及 RFC 2617 的 MD5 Digest 公式实现。未复制 gortsplib 或 MediaMTX 源代码，未宣称完整移植。它们使用 MIT 许可证，是行为研究和互操作依据。

| 能力 | 本项目 | gortsplib/MediaMTX 对照边界 |
| --- | --- | --- |
| OPTIONS、DESCRIBE、SETUP、PLAY、PAUSE、TEARDOWN | 会话约束及网络 API | 覆盖常见控制链路 |
| ANNOUNCE、RECORD | 多轨 RTP 发布 | 接收现成 RTP，CLI 合成 G.711 演示 |
| GET_PARAMETER、OPTIONS 保活 | 显式调用及 due 查询 | 无后台守护线程，调用者安排周期 |
| Basic/Digest | MD5、qop=auth、旧式无 qop、opaque、nonce count | 不支持 MD5-sess、SHA-256、auth-int、Bearer |
| TCP/UDP | 单播交织、连续端口与通道校验 | UDP 限 IPv4、固定服务端来源，拒绝 source 重定向；不做组播 |
| SDP | 依赖 moon-sdp，解析 aggregate 和多轨 control | 不实现新的 SDP 语言 |
| RTP/RTCP | 依赖 rtc.mbt 解包、编包、载荷分片与 RTCP compound | 不复制 WebRTC 栈；不做解码播放 |
| 媒体处理 | 有界队列、序号间隙、SSRC 切换、时钟回绕、帧组装 | 无抖动缓冲、乱序恢复、拥塞控制或 FEC |
| 超时/取消/重连 | 整笔事务限时、取消关闭资源、fresh-session 重连 | 不恢复旧服务端 Session，不承诺无缝断流 |
| 扩展 | 明确报错 | 无 RTSP 2.0、RTSPS、SRTP、HTTP 隧道、ONVIF、完整服务器 |

实际依赖：moonbitlang/async 0.22.4（Apache-2.0），coke089/moon-sdp 0.1.0（Apache-2.0），gmlewis/md5 0.20.2（Apache-2.0），moonbit-community/rtc 0.0.1（MIT OR Apache-2.0）。保留各依赖自己的许可证；本仓库原创实现使用 MIT。测试依赖 MediaMTX v1.21.3 的官方二进制，脚本固定校验 SHA-256，仅在临时目录运行，不加入发布包。

独立验证入口：`python scripts/interop.py --target wasm`。它启动真实 MediaMTX，并测试 Basic/Digest × TCP/UDP 发布组合，双轨描述、两种传输播放、PAUSE/PLAY/GET_PARAMETER/TEARDOWN，以及错误凭据拒绝。测试脚本不是参考协议实现，媒体服务由独立成熟软件提供。RFC Digest Mufasa 向量、全字节切分与错误边界见测试文件。
