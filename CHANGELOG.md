# Changelog

## 0.1.2

- Use the explicit moonbitlang/async 0.22.4 runtime in the external consumer setup, matching the networking library and CLI. The built-in core/async runtime cannot drive this dependency.
- Runtime API and behavior unchanged; corrected consumer setup verified with a real socket request.

## 0.1.1

- Complete the external async consumer package configuration for strict checks.
- Runtime API and behavior unchanged from 0.1.0.

# 更新记录

## 0.1.0

初始 RTSP 1.0 客户端：有界增量解码、Basic/Digest、SDP 多轨、TCP/UDP 播放与发布、Session/CSeq、保活/暂停、超时取消、fresh-session 重连、RTP/RTCP 与帧/观察统计、CLI。附独立 MediaMTX 互操作与错误路径测试。明确不含服务端、解码器或 RTSP 加密扩展。
