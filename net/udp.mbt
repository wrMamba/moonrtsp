///|
priv struct UdpPair {
  rtp : @socket.UdpServer
  rtcp : @socket.UdpServer
  mut peer_rtp : @socket.Addr?
  mut peer_rtcp : @socket.Addr?
}

///|
async fn UdpPair::bind() -> UdpPair {
  // Bind the even ephemeral RTP port first, then its adjacent RTCP port.
  for _attempt = 0; _attempt < 32; _attempt = _attempt + 1 {
    let rtp = @socket.UdpServer(@socket.Addr::parse("0.0.0.0:0"))
    let port = rtp.addr.port()
    if port % 2 != 0 || port == 65535 {
      rtp.close()
      continue
    }
    let control = @socket.UdpServer(
      @socket.Addr::parse("0.0.0.0:" + (port + 1).to_string()),
    ) catch {
      _ => {
        rtp.close()
        continue
      }
    }
    return { rtp, rtcp: control, peer_rtp: None, peer_rtcp: None, }
  }
  raise @rtsp.State("could not allocate consecutive UDP ports")
}

///|
fn UdpPair::close(self : UdpPair) -> Unit {
  self.rtp.close()
  self.rtcp.close()
}

///|
async fn UdpPair::negotiate(
  self : UdpPair,
  endpoint : @rtsp.Endpoint,
  negotiated : @rtsp.Negotiated,
) -> Unit {
  let (a, b) = match negotiated.server_ports {
    Some(p) => p
    None => raise @rtsp.Invalid("UDP server ports")
  }
  // Source overrides are rejected to avoid sending media to arbitrary reflected hosts.
  if negotiated.source is Some(source) {
    if source != endpoint.hostname() {
      raise @rtsp.Invalid("UDP source override unsupported")
    }
  }
  self.peer_rtp = Some(
    @socket.Addr::resolve(endpoint.hostname(), port=a, protocol=OnlyV4),
  )
  self.peer_rtcp = Some(
    @socket.Addr::resolve(endpoint.hostname(), port=b, protocol=OnlyV4),
  )
}

///|
async fn UdpPair::receive(self : UdpPair, control : Bool) -> Bytes {
  let sock = if control { self.rtcp } else { self.rtp }
  let peer = if control { self.peer_rtcp } else { self.peer_rtp }
  let data = FixedArray::make(65536, b'\x00')
  while true {
    let (length, from) = sock.recvfrom(data)
    if peer == Some(from) {
      return data.unsafe_reinterpret_as_bytes()[:length].to_owned()
    }
  } nobreak {
    raise @rtsp.Closed
  }
}

///|
async fn UdpPair::send(self : UdpPair, control : Bool, bytes : Bytes) -> Unit {
  let sock = if control { self.rtcp } else { self.rtp }
  let peer = if control { self.peer_rtcp } else { self.peer_rtp }
  match peer {
    Some(addr) => sock.sendto(bytes, addr)
    None => raise @rtsp.State("UDP not negotiated")
  }
}
