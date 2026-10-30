///|
pub async fn Client::options(self : Client) -> Array[String] {
  @rtsp.parse_public(self.request("OPTIONS").headers)
}

///|
pub async fn Client::describe(self : Client) -> @rtsp.Description {
  let h = @rtsp.Headers::new()
  h.add("Accept", "application/sdp")
  let response = self.request("DESCRIBE", headers=h)
  errdefer self.close()
  if !response.headers
    .get("Content-Type")
    .unwrap_or("")
    .has_prefix("application/sdp") {
    raise @rtsp.Invalid("DESCRIBE Content-Type")
  }
  let base = response.headers.get("Content-Base").unwrap_or(self.endpoint.url())
  let description = @rtsp.describe(response.body, base)
  self.description = Some(description)
  description
}

///|
pub async fn Client::announce(self : Client, sdp : String) -> @rtsp.Description {
  let description = @rtsp.describe(
    @utf8.encode(sdp),
    if self.endpoint.url().has_suffix("/") {
      self.endpoint.url()
    } else {
      self.endpoint.url() + "/"
    },
  )
  let h = @rtsp.Headers::new()
  h.add("Content-Type", "application/sdp")
  ignore(self.request("ANNOUNCE", body=@utf8.encode(sdp), headers=h))
  self.description = Some(description)
  description
}

///|
pub async fn Client::setup(
  self : Client,
  track : Int32,
  udp~ : Bool = false,
  record~ : Bool = false,
) -> @rtsp.Negotiated {
  let description = match self.description {
    Some(v) => v
    None => raise @rtsp.State("describe or announce first")
  }
  if track < 0 || track >= description.tracks.length() {
    raise @rtsp.Invalid("setup track")
  }
  for b in self.setups {
    if b.track == track {
      raise @rtsp.State("track already setup")
    }
  }
  let pair = if udp { Some(UdpPair::bind()) } else { None }
  errdefer (if pair is Some(p) { p.close() })
  let transport = match pair {
    Some(p) => @rtsp.Udp(p.rtp.addr.port(), p.rtcp.addr.port())
    None => @rtsp.Tcp(self.setups.length() * 2, self.setups.length() * 2 + 1)
  }
  let h = @rtsp.Headers::new()
  h.add("Transport", transport.encode(record~))
  let response = self.request(
    "SETUP",
    uri=description.tracks[track].control,
    headers=h,
  )
  errdefer self.close()
  let header = match response.headers.get("Transport") {
    Some(v) => v
    None => raise @rtsp.Invalid("SETUP missing Transport")
  }
  let negotiated = @rtsp.negotiate(header, transport)
  if pair is Some(p) {
    p.negotiate(self.endpoint, negotiated)
  } else {
    self.channels.bind(track, transport)
  }
  self.setups.push({ track, transport, udp: pair, })
  negotiated
}

///|
fn Client::aggregate(self : Client) -> String {
  match self.description {
    Some(d) => d.aggregate
    None => self.endpoint.url()
  }
}

///|
pub async fn Client::play(
  self : Client,
  range~ : @rtsp.PlayRange = @rtsp.Live,
) -> Array[@rtsp.RtpInfo] {
  let h = @rtsp.Headers::new()
  h.add("Range", range.encode())
  let response = self.request("PLAY", uri=self.aggregate(), headers=h)
  match response.headers.get("RTP-Info") {
    Some(v) => @rtsp.parse_rtp_info(v, self.aggregate())
    None => []
  }
}

///|
pub async fn Client::record(self : Client) -> Unit {
  ignore(self.request("RECORD", uri=self.aggregate()))
}

///|
pub async fn Client::pause(self : Client) -> Unit {
  ignore(self.request("PAUSE", uri=self.aggregate()))
}

///|
pub async fn Client::keepalive(
  self : Client,
  use_options~ : Bool = false,
) -> Unit {
  ignore(
    self.request(
      if use_options {
        "OPTIONS"
      } else {
        "GET_PARAMETER"
      },
      uri=self.aggregate(),
    ),
  )
}

///|
pub fn Client::keepalive_due(self : Client) -> Bool {
  self.session.keepalive_due(@async.now())
}

///|
pub async fn Client::teardown(self : Client) -> Unit {
  defer self.close()
  ignore(self.request("TEARDOWN", uri=self.aggregate()))
}
