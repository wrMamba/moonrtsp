///|
fn nonce() -> String raise {
  let bytes = match @env.rand(16) {
    Some(v) => v
    None => raise @rtsp.State("secure random unavailable")
  }
  let out = StringBuilder()
  let digits = "0123456789abcdef"
  for b in bytes {
    let n = b.to_int()
    let a = n / 16
    let c = n % 16
    out.write_string(digits[a:a + 1].to_owned())
    out.write_string(digits[c:c + 1].to_owned())
  }
  out.to_string()
}

///|
async fn main {
  let args = @env.args()
  if args.length() < 3 {
    println(
      "usage: moonrtsp inspect|play|publish|publish-multi|follow rtsp://host/path [tcp|udp] [packet-count]",
    )
    return
  }
  let mode = args[1]
  let uri = args[2]
  let udp = args.length() > 3 && args[3] == "udp"
  let count = if args.length() > 4 {
    @rtsp.parse_count(args[4], 1000000)
  } else {
    100
  }
  let credentials = match @env.get_env_var("MOONRTSP_USER") {
    Some(user) => {
      let password = @env.get_env_var("MOONRTSP_PASSWORD").unwrap_or("")
      Some(@rtsp.Credentials::new(user, password))
    }
    None => None
  }
  let cnonce = nonce()
  if mode == "follow" {
    @net.follow(
      uri,
      [0],
      @rtsp.ReconnectPolicy::new(),
      client => {
        for i = 0; i < count; i = i + 1 {
          let event = if udp { client.receive_udp(0) } else { client.receive() }
          if event is Rtp(track, packet) {
            println(
              "rtp track=" +
              track.to_string() +
              " seq=" +
              packet.sequence_number().to_string(),
            )
          }
        }
      },
      udp~,
      credentials?,
      cnonce~,
    )
    return
  }
  let client = @net.Client::connect(uri, credentials?, cnonce~)
  defer client.close()
  if mode == "publish" || mode == "publish-multi" {
    let mut sdp = "v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\ns=MoonRTSP synthetic G711\r\nt=0 0\r\na=control:*\r\nm=audio 0 RTP/AVP 0\r\na=rtpmap:0 PCMU/8000\r\na=control:trackID=0\r\n"
    if mode == "publish-multi" {
      sdp += "m=audio 0 RTP/AVP 8\r\na=rtpmap:8 PCMA/8000\r\na=control:trackID=1\r\n"
    }
    ignore(client.announce(sdp))
    ignore(client.setup(0, udp~, record=true))
    if mode == "publish-multi" {
      ignore(client.setup(1, udp~, record=true))
    }
    client.record()
    println("recording")
    for i = 0; i < count; i = i + 1 {
      let packet = @rtp.Packet::new(
        payload_type=b'\x00',
        sequence_number=(i % 65536).to_uint16(),
        timestamp=i.reinterpret_as_uint() * 160U,
        ssrc=123456U,
        marker=i == 0,
        payload=Bytes::make(160, b'\xff'),
      )
      client.send_packet(0, packet)
      if mode == "publish-multi" {
        let other = @rtp.Packet::new(
          payload_type=b'\x08',
          sequence_number=(i % 65536).to_uint16(),
          timestamp=i.reinterpret_as_uint() * 160U,
          ssrc=654321U,
          marker=i == 0,
          payload=Bytes::make(160, b'\xd5'),
        )
        client.send_packet(1, other)
      }
      @async.sleep(20)
    }
    client.teardown()
    println("published packets=" + count.to_string())
  } else if mode == "inspect" || mode == "play" {
    let methods = client.options()
    println("methods=" + methods.join(","))
    let description = client.describe()
    for track in description.tracks {
      println(
        "track=" +
        track.index.to_string() +
        " kind=" +
        track.kind +
        " formats=" +
        track.formats.join(","),
      )
    }
    if mode == "inspect" {
      return
    }
    for track in description.tracks {
      ignore(client.setup(track.index, udp~))
    }
    ignore(client.play())
    let mut received = 0
    while received < count {
      let event = if udp {
        client.receive_udp(description.tracks[0].index)
      } else {
        client.receive()
      }
      if event is Rtp(track, packet) {
        received += 1
        println(
          "rtp track=" +
          track.to_string() +
          " seq=" +
          packet.sequence_number().to_string() +
          " bytes=" +
          packet.payload().length().to_string(),
        )
      }
      if client.keepalive_due() {
        client.keepalive()
      }
    }
    client.pause()
    ignore(client.play())
    client.keepalive()
    client.teardown()
    println("received packets=" + received.to_string())
  } else {
    raise @rtsp.Invalid("unknown command")
  }
}
