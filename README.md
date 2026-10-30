# MoonRTSP

面向摄像头接入、媒体采集和流媒体测试的 **RTSP 1.0 客户端库与命令行工具**。包含实际 TCP/UDP 网络连接、认证、播放和发布；输出编码 RTP 数据，交给应用保存、转发或解码。

模块：`wrMamba/moonrtsp@0.1.2`。原创协议会话与网络集成实现，MIT 许可。成熟软件能力逐项对照见 [参考与边界](docs/references.md)，查重证据见 [选题记录](docs/competition/duplicate-check.md)。

## 能做什么

- OPTIONS / DESCRIBE / SETUP / PLAY / PAUSE / TEARDOWN；ANNOUNCE / RECORD 发布；GET_PARAMETER 或 OPTIONS 保活。
- Basic、Digest MD5（qop=auth 或旧式无 qop）、opaque 与 nonce count；最多两次认证重试。
- SDP 多轨描述和轨道选择；TCP interleaved、IPv4 UDP 单播；连续端口、通道及服务端来源校验。
- 增量 RTSP/交织帧解码、CSeq 与 Session 校验；事务超时、任务取消关闭和有界 fresh-session 重连。
- RTP/RTCP 类型化收发、队列丢弃计数、序号/SSRC/时钟观察、依赖 codec 的有界访问单元组装。
- CLI 检查媒体描述、收包、合成 G.711 单轨/双轨发布、断线重连。

不含 RTSP 服务端、RTSP 2.0、RTSPS/SRTP、HTTP 隧道、组播、ONVIF、解码器和图形播放器。不承诺兼容所有摄像头私有扩展。完整限制和参考软件差距见下文。

## 环境与安装

安装官方 MoonBit 工具链，执行 `moon version --all`。开发验证使用 moonc 0.10.18；网络包使用 `moonbitlang/async` 0.22.4。

```sh
moon new camera-client
cd camera-client
moon add wrMamba/moonrtsp@0.1.2
moon add moonbitlang/async@0.22.4
```

在调用包的 `moon.pkg` 中加入所需导入：

```moonbit
import {
  "moonbitlang/async",
  "wrMamba/moonrtsp" @rtsp,
  "wrMamba/moonrtsp/net" @net,
}
supported_targets = "native+wasm"
pkgtype(kind: "executable")
```

网络消费者的 `async fn main` 必须使用上述 `moonbitlang/async` 运行时；不要改为 `moonbitlang/core/async`，两者的协程上下文不同。

根包为便携核心，支持 wasm-gc / wasm / js / native。`net` 和 CLI 支持 wasm / native；**wasm 使用 moonrun 的宿主 socket 能力**，不是浏览器内直接连摄像头。native 需要平台 C 工具链；Windows 需要 MSVC/SDK。模块默认 wasm。

## 快速开始：真实媒体服务器

在一个终端启动 MediaMTX，使用默认 RTSP 端口 8554；以下无认证示例面向本机测试。另开终端在本仓库执行：

```sh
moon run cmd/moonrtsp --target wasm -- publish-multi rtsp://127.0.0.1:8554/demo tcp 3000
```

发布运行期间，在第三个终端：

```sh
moon run cmd/moonrtsp --target wasm -- inspect rtsp://127.0.0.1:8554/demo
moon run cmd/moonrtsp --target wasm -- play rtsp://127.0.0.1:8554/demo tcp 20
moon run cmd/moonrtsp --target wasm -- play rtsp://127.0.0.1:8554/demo udp 20
```

`publish` 生成 PCMU 静音，`publish-multi` 生成 PCMU/PCMA 两轨，每轨 20ms 一个包；只用于验证接入与传输。`play` 打印 RTP 轨道、序号和载荷长度，收到指定数量后暂停、恢复、保活并正常 TEARDOWN。TCP 接收所有轨道，CLI UDP 演示接收第一轨；库 API 可指定其他轨道及 RTCP。

需要认证时，在进程环境设置 `MOONRTSP_USER` 和 `MOONRTSP_PASSWORD`。不在 URL 或命令参数中放用户名/密码。CLI 自动产生随机 cnonce。

```powershell
$env:MOONRTSP_USER = "camera-user"
$env:MOONRTSP_PASSWORD = "your-local-password"
moon run cmd/moonrtsp --target wasm -- inspect rtsp://127.0.0.1:8554/demo
```

`follow URL tcp 20` 每次连接接收 20 个事件，异常时按策略重新连接、DESCRIBE、SETUP、PLAY，成功回调结束后退出；它不恢复旧 Session，也不保证媒体无缝连续。

## 库 API：采集一段 RTP

以下可放在以上消费者的 `main.mbt`；`async fn main` 由编译器驱动：

```moonbit
///|
async fn main {
  let client = @net.Client::connect("rtsp://127.0.0.1:8554/demo")
  defer client.close()
  let description = client.describe()
  for track in description.select([0]) {
    ignore(client.setup(track.index))
  }
  ignore(client.play())
  for i = 0; i < 20; i = i + 1 {
    match client.receive() {
      Rtp(track, packet) => println("track=" + track.to_string() + " bytes=" + packet.payload().length().to_string())
      Rtcp(_, _) => ()
    }
    if client.keepalive_due() { client.keepalive() }
  }
  client.teardown()
}
```

认证连接传入 `credentials=@rtsp.Credentials::new(user, password)` 和调用者生成的不可预测 `cnonce=...`。同一个 Client 的完整工作流由调用者串行安排；事务和 TCP 媒体操作有互斥保护，不承诺并发多工作流安全。调用者安排保活周期；本库不启动隐式后台线程。

三个复用工作流：摄像头工具先 `options/describe` 检查轨道和媒体格式；采集服务 `setup/play/receive` 获取编码媒体并查询 `statistics`；测试工具 `announce/setup(record=true)/record/send_packet` 向服务端发布已有 RTP。可独立复用根包处理离线协议日志，运行 `moon run examples/protocol --target wasm-gc`。

UDP 调用 `setup(index, udp=true)`，按轨道 `receive_udp(index)` 或 `receive_udp(index, control=true)`，并通过 `send(index, payload, control=true)` 发送 RTCP。端口对按 IPv4 临时偶数端口和下一端口分配，最多尝试 32 次；拒绝重定向到其他 source 主机。

## 数据与资源约束

单个消息体最大 1MiB，头部最大 32KiB，头字段最多 128；默认解码缓冲 2MiB，可配上限 8MiB。轨道最多 16；队列默认有界，满时丢最早事件并增加 `discarded()`。组帧默认 4MiB/4096 包，上限 16MiB/16384 包；遇缺包丢弃整帧，不做乱序恢复。详见 [架构](docs/architecture.md)。

统计中的 forward gaps 为观察到的序号间隙，late/duplicate 合并记录，**不能作为网络真实丢包率**；不实现 jitter buffer、拥塞控制、FEC 或时钟同步。Digest 仅 MD5，明文 RTSP 不保护媒体或凭据传输，部署边界见 [安全说明](SECURITY.md)。

## 验证与复现

```sh
moon info
moon fmt --check
moon check --target wasm --deny-warn
moon test --target wasm --deny-warn
moon build --target wasm --deny-warn
moon run examples/protocol --target wasm --deny-warn
python scripts/audit.py
python scripts/interop.py --target wasm
```

`interop.py` 自动下载固定 SHA-256 的 MediaMTX v1.21.3 官方测试二进制，在临时目录和本机端口启动，执行 Basic/Digest × TCP/UDP 发布四组测试。每组验证双轨描述、TCP/UDP 播放、暂停恢复、保活、TEARDOWN、错误密码拒绝。需要空闲 18554/18000/18001 端口和网络下载能力；可用 `--server /absolute/path/to/mediamtx` 指定已有测试服务程序。

单元测试含 RFC Digest 已知向量、所有字节分割点、边界拒绝、RTP 回绕/缺包、真实 socket 超时和父任务取消、UDP 来源过滤、断线重建会话。CI 对四个后端执行检查/测试/构建，对 wasm/native 运行独立服务器互操作。Windows 本地没有 MSVC 时用 wasm；native 结果以 Ubuntu CI 为准。测试状态请查看仓库实际 Actions 结果。

## 许可、依赖和 AI

原创代码为 [MIT](LICENSE)。使用 moonbitlang/async、coke089/moon-sdp、gmlewis/md5、moonbit-community/rtc，版本及各自许可证见 [参考](docs/references.md)，不把第三方包改称原创实现。借鉴 RTSP RFC 与 gortsplib 行为，不声称完整移植。项目使用 AI 辅助实现、文档与测试，披露见 [AI-USE.md](AI-USE.md)。
