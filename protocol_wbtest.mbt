///|
test "RFC Digest MD5 and Basic vectors" {
  let a = Authenticator::new(
    Credentials::new("Mufasa", "Circle Of Life"),
    "0a4f113b",
  )
  a.challenge(
    "Digest realm=\"testrealm@host.com\", qop=\"auth,auth-int\", nonce=\"dcd98b7102dd2f0e8b11d0f600bfb0c093\", opaque=\"5ccc069c403ebaf9f0171e9517f40e41\"",
  )
  let value = a.authorization("GET", "/dir/index.html")
  assert_true(value.contains("6629fae49393a05397450978507c4ef1"))
  assert_true(value.contains("nc=00000001"))
  assert_true(a.authorization("GET", "/dir/index.html").contains("nc=00000002"))
  a.challenge("Basic realm=\"camera\"")
  assert_eq(
    a.authorization("PLAY", "rtsp://host/a"),
    "Basic TXVmYXNhOkNpcmNsZSBPZiBMaWZl",
  )
}

///|
test "parameter quoting duplicate and truncation" {
  let p = parse_parameters("realm=\"a,b\",nonce=\"x\\\"y\"")
  assert_eq(p["realm"], "a,b")
  assert_eq(p["nonce"], "x\"y")
  expect_error(() => ignore(parse_parameters("realm=a,realm=b")))
  expect_error(() => ignore(parse_parameters("realm=\"broken")))
}

///|
test "headers validation URL resolution and critical duplicates" {
  let h = Headers::new()
  h.add("CSeq", "1")
  assert_eq(h.get("cseq"), Some("1"))
  expect_error(() => ignore(h.add("X", "bad\r\n")))
  assert_eq(
    resolve_control("rtsp://host/live/", "trackID=1"),
    "rtsp://host/live/trackID=1",
  )
  assert_eq(resolve_control("rtsp://host/a/b", "../c"), "rtsp://host/c")
  assert_eq(Endpoint::parse("rtsp://[::1]:8554/a").hostname(), "::1")
  expect_error(() => ignore(Endpoint::parse("rtsp://user:pw@host/a")))
  let d = Decoder::new()
  expect_error(() => {
    ignore(d.feed(b"RTSP/1.0 200 OK\r\nCSeq: 1\r\nCSeq: 2\r\n\r\n"))
  })
  expect_error(() => ignore(d.feed(b"")))
  d.reset()
  assert_eq(d.pending(), 0)
}

///|
test "all split points coalesced RTSP and interleaved data" {
  let r = Request::new("OPTIONS", "rtsp://camera/live", 7)
  let data = r.encode() +
    interleave(0, b"abc") +
    b"RTSP/1.0 200 OK\r\nCSeq: 7\r\nContent-Length: 3\r\n\r\nsdp"
  for cut = 0; cut <= data.length(); cut = cut + 1 {
    let d = Decoder::new()
    let a = d.feed(data[:cut].to_owned())
    let b = d.feed(data[cut:].to_owned())
    assert_eq(a.length() + b.length(), 3)
    d.finish()
  }
}

///|
test "transport negotiation and NPT boundaries" {
  let t = negotiate("RTP/AVP/TCP;unicast;interleaved=2-3;ssrc=1234", Tcp(2, 3))
  assert_eq(t.ssrc, Some("1234"))
  expect_error(() => {
    ignore(negotiate("RTP/AVP/TCP;unicast;interleaved=0-1", Tcp(2, 3)))
  })
  expect_error(() => ignore(negotiate("RTP/AVP;multicast", Udp(5000, 5001))))
  assert_eq(Interval(1L, 2001L).encode(), "npt=0.001-2.001")
  expect_error(() => ignore(Interval(2L, 1L).encode()))
  assert_eq(parse_session("abc;timeout=30").timeout_seconds, 30)
  expect_error(() => ignore(parse_session("abc;timeout=0")))
  let info = parse_rtp_info(
    "url=track;seq=65535;rtptime=4294967295", "rtsp://host/live/",
  )
  assert_eq(info[0].timestamp, Some(4294967295U))
}

///|
fn reply(
  request : Request,
  status~ : Int32 = 200,
  session? : String,
) -> Response raise {
  let headers = Headers::new()
  headers.add("CSeq", request.cseq().to_string())
  if session is Some(v) {
    headers.add("Session", v)
  }
  { status, reason: "OK", headers, body: b"", }
}

///|
test "session phase CSeq keepalive and timeout" {
  let s = Session::new("rtsp://host/live")
  expect_error(() => ignore(s.request("PLAY")))
  let d = s.request("DESCRIBE")
  expect_error(() => ignore(s.request("OPTIONS")))
  ignore(s.accept(reply(d)))
  let setup = s.request("SETUP", uri="rtsp://host/live/track")
  ignore(s.accept(reply(setup, session="abc;timeout=20")))
  assert_eq(s.setup_count(), 1)
  assert_true(s.keepalive_due(10000L))
  let play = s.request("PLAY")
  ignore(s.accept(reply(play)))
  assert_eq(s.phase(), Playing)
  let pause = s.request("PAUSE")
  ignore(s.accept(reply(pause)))
  assert_eq(s.phase(), Paused)
  let req = s.request("OPTIONS", now=100L, timeout_ms=20)
  let wrong = reply(req)
  wrong.headers.set("CSeq", "999")
  expect_error(() => ignore(s.accept(wrong)))
  expect_error(() => ignore(s.check_deadline(120L)))
  assert_eq(s.phase(), Ended)
}

///|
test "challenge retry bounded and CSeq incremented" {
  let s = Session::new(
    "rtsp://host/a",
    auth=Authenticator::new(Credentials::new("u", "p"), "random123"),
  )
  let req = s.request("OPTIONS")
  let r = reply(req, status=401)
  r.headers.add("WWW-Authenticate", "Digest realm=\"cam\",nonce=\"first\"")
  let retry = s.accept(r).unwrap()
  assert_eq(retry.cseq(), 2)
  assert_true(retry.headers.get("Authorization").unwrap().has_prefix("Digest "))
  ignore(s.accept(reply(retry)))
  assert_eq(s.phase(), Connected)
}

///|
fn expect_error(f : () -> Unit raise) -> Unit raise {
  try f() catch {
    _ => ()
  } noraise {
    _ => fail("expected error")
  }
}

///|
test "UDP server ports and requested transport validated before negotiation" {
  expect_error(() => {
    ignore(negotiate("RTP/AVP;unicast;server_port=0-1", Udp(5000, 5001)))
  })
  expect_error(() => {
    ignore(negotiate("RTP/AVP/TCP;unicast;interleaved=0-2", Tcp(0, 2)))
  })
  let result = negotiate(
    "RTP/AVP;unicast;server_port=5000-5001",
    Udp(6000, 6001),
  )
  assert_eq(result.server_ports, Some((5000, 5001)))
}
