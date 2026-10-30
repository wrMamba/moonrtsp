///|
fn main raise {
  let endpoint = @rtsp.Endpoint::parse("rtsp://camera.local/live")
  assert_eq(endpoint.port, 554)
  let request = @rtsp.Request::new("OPTIONS", endpoint.url(), 1)
  let decoder = @rtsp.Decoder::new()
  let events = decoder.feed(request.encode())
  assert_eq(events.length(), 1)
  match events[0] {
    Command(parsed) => assert_eq(parsed.cseq(), 1)
    _ => fail("expected request")
  }
  decoder.finish()
  let transport = @rtsp.negotiate(
    "RTP/AVP/TCP;unicast;interleaved=0-1",
    @rtsp.Tcp(0, 1),
  )
  assert_eq(transport.server_ports, None)
  assert_eq(@rtsp.PlayRange::Interval(1000L, 2500L).encode(), "npt=1.000-2.500")
  println("MoonRTSP protocol consumer passed")
}
