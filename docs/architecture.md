# 架构与契约

`headers/message/decoder/url/transport/parameters` 是无 I/O 的有界 wire 核心。Decoder 在协议错误后 poison，需 reset；finish 拒绝截断输入。重复关键 CSeq、Session、Content-Length 被拒绝。Header set 先验证再修改。

`auth/session/session_header/range` 管理认证与控制状态。一次仅一笔 pending 事务，CSeq 单调增加，认证重试也使用新 CSeq。PLAY 与 RECORD 分属描述和发布路径；收到错误 Session/CSeq 或事务超时后网络层关闭连接。

`description` 复用 moon-sdp，限制轨道并解析 aggregate/media control；`media/frames/statistics` 复用 rtc.mbt 的 RTP/RTCP/载荷编解码，在其上实现通道映射、有界队列、观察统计和帧完整性约束。

`net` 使用 async 的结构化并发与 socket；errdefer 关闭错误/取消中的 TCP/UDP 资源。TCP 接收支持交织媒体与控制消息共用连接；UDP 固定服务端地址，避免接收其他来源。事务及单次接收限时为 10 秒，可配置到 600 秒。应用必须串行安排描述、设轨、播放/发布和接收工作流，不能用多个任务任意驱动同一 Client。

`follow` 每次错误后销毁旧 Client，按最多 20 次、有限指数退避重新连接并建立媒体会话；取消向上传播。回调负责安排保活与媒体处理，不承诺恢复远端播放时间或去除重连边界重复帧。

CLI 是真实库调用，发布合成 G.711；不会解码 H.264，也不是 RTSP 服务端。portable example 只验证协议核心，互操作脚本运行独立 MediaMTX，socket 测试验证错误路径。公开接口由生成的 mbti 描述。
