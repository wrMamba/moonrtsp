///|
async fn command(conn : @socket.Tcp, decoder : @rtsp.Decoder) -> @rtsp.Request {
  while true {
    let chunk = match conn.read_some() {
      Some(v) => v
      None => raise @rtsp.Closed
    }
    for event in decoder.feed(chunk) {
      if event is Command(request) {
        return request
      }
    }
  } nobreak {
    raise @rtsp.Closed
  }
}

///|
async fn answer(
  conn : @socket.Tcp,
  request : @rtsp.Request,
  status~ : Int32 = 200,
  extra? : @rtsp.Headers,
) -> Unit {
  let h = match extra {
    Some(v) => v
    None => @rtsp.Headers::new()
  }
  h.set("CSeq", request.cseq().to_string())
  conn.write(@rtsp.Response::new(status, "Fixture", h).encode())
}

///|
async test "socket auth challenge and actual response parsing" {
  @async.with_task_group(group => {
    let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    group.spawn_bg(() => {
      let (conn, _) = server.accept()
      defer conn.close()
      let decoder = @rtsp.Decoder::new()
      let first = command(conn, decoder)
      assert_eq(first.verb, "OPTIONS")
      let h = @rtsp.Headers::new()
      h.add("WWW-Authenticate", "Basic realm=\"fixture\"")
      answer(conn, first, status=401, extra=h)
      let retry = command(conn, decoder)
      assert_eq(retry.cseq(), first.cseq() + 1)
      assert_eq(retry.headers.get("Authorization"), Some("Basic dTpw"))
      let h = @rtsp.Headers::new()
      h.add("Public", "OPTIONS, DESCRIBE, SETUP, PLAY")
      answer(conn, retry, extra=h)
    })
    let client = Client::connect(
      "rtsp://127.0.0.1:" + server.addr.port().to_string() + "/test",
      credentials=@rtsp.Credentials::new("u", "p"),
      cnonce="fixture123",
    )
    defer client.close()
    assert_true(client.options().contains("PLAY"))
  })
}

///|
async test "transaction timeout closes resources" {
  @async.with_task_group(group => {
    let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    group.spawn_bg(() => {
      let (conn, _) = server.accept()
      defer conn.close()
      ignore(command(conn, @rtsp.Decoder::new()))
      @async.sleep(2000)
    })
    let client = Client::connect(
      "rtsp://127.0.0.1:" + server.addr.port().to_string() + "/test",
      timeout_ms=500,
    )
    defer client.close()
    try client.options() catch {
      _ => ()
    } noraise {
      _ => fail("timeout expected")
    }
    assert_eq(client.phase(), @rtsp.Ended)
  })
}

///|
async test "unexpected CSeq and truncated socket replies close connection" {
  for truncated in [true, false] {
    @async.with_task_group(group => {
      let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      group.spawn_bg(() => {
        let (conn, _) = server.accept()
        defer conn.close()
        ignore(command(conn, @rtsp.Decoder::new()))
        conn.write(
          if truncated {
            b"RTSP/1.0 200 OK\r\nCSeq: 1\r\nContent-Length: 10\r\n\r\nx"
          } else {
            b"RTSP/1.0 200 OK\r\nCSeq: 999\r\n\r\n"
          },
        )
      })
      let client = Client::connect(
        "rtsp://127.0.0.1:" + server.addr.port().to_string() + "/test",
      )
      defer client.close()
      try client.options() catch {
        _ => ()
      } noraise {
        _ => fail("protocol error expected")
      }
      assert_eq(client.phase(), @rtsp.Ended)
    })
  }
}

///|
async test "parent cancellation closes pending socket transaction" {
  @async.with_task_group(group => {
    let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    group.spawn_bg(() => {
      let (conn, _) = server.accept()
      defer conn.close()
      ignore(command(conn, @rtsp.Decoder::new()))
      @async.sleep(1000)
    })
    let client = Client::connect(
      "rtsp://127.0.0.1:" + server.addr.port().to_string() + "/test",
    )
    defer client.close()
    let result = @async.with_timeout_opt(50, () => client.options())
    assert_true(result is None)
    assert_eq(client.phase(), @rtsp.Ended)
  })
}

///|
async test "UDP pair allocation source matching and datagram transfer" {
  let pair = UdpPair::bind()
  defer pair.close()
  assert_eq(pair.rtp.addr.port() % 2, 0)
  assert_eq(pair.rtcp.addr.port(), pair.rtp.addr.port() + 1)
  let sender = @socket.UdpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer sender.close()
  pair.peer_rtp = Some(sender.addr)
  let rogue = @socket.UdpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer rogue.close()
  let target = @socket.Addr::parse(
    "127.0.0.1:" + pair.rtp.addr.port().to_string(),
  )
  rogue.sendto(b"rogue", target)
  sender.sendto(b"accepted", target)
  assert_eq(@async.with_timeout(1000, () => pair.receive(false)), b"accepted")
}

///|
async test "follow creates fresh sessions after callback disconnect" {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let uri = "rtsp://127.0.0.1:" + server.addr.port().to_string() + "/live"
  let mut callbacks = 0
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      for cycle = 0; cycle < 2; cycle = cycle + 1 {
        let (conn, _) = server.accept()
        defer conn.close()
        let decoder = @rtsp.Decoder::new()
        let describe = command(conn, decoder)
        assert_eq(describe.verb, "DESCRIBE")
        assert_eq(describe.cseq(), 1)
        let h = @rtsp.Headers::new()
        h.add("CSeq", "1")
        h.add("Content-Type", "application/sdp")
        h.add("Content-Base", uri + "/")
        let body = @utf8.encode(
          "v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\ns=fixture\r\nt=0 0\r\na=control:*\r\nm=audio 0 RTP/AVP 0\r\na=control:trackID=0\r\n",
        )
        conn.write(@rtsp.Response::new(200, "OK", h, body~).encode())
        let setup = command(conn, decoder)
        let h = @rtsp.Headers::new()
        h.add("Session", "session" + cycle.to_string())
        h.add("Transport", "RTP/AVP/TCP;unicast;interleaved=0-1")
        answer(conn, setup, extra=h)
        let play = command(conn, decoder)
        answer(conn, play)
      }
    })
    follow(uri, [0], @rtsp.ReconnectPolicy::new(attempts=1, initial_ms=1), client => {
      callbacks += 1
      assert_eq(client.phase(), @rtsp.Playing)
      if callbacks == 1 {
        client.close()
        raise @rtsp.Closed
      }
    })
  })
  assert_eq(callbacks, 2)
}
