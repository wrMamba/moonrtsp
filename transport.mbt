///|
pub(all) enum Transport {
  Tcp(Int32, Int32)
  Udp(Int32, Int32)
}

///|
pub fn Transport::encode(
  self : Transport,
  record~ : Bool = false,
) -> String raise RtspError {
  let base = match self {
    Tcp(a, b) => {
      require(a >= 0 && b == a + 1 && b <= 255, "TCP channel pair")
      "RTP/AVP/TCP;unicast;interleaved=" + a.to_string() + "-" + b.to_string()
    }
    Udp(a, b) => {
      require(a > 0 && b == a + 1 && b <= 65535, "UDP port pair")
      "RTP/AVP;unicast;client_port=" + a.to_string() + "-" + b.to_string()
    }
  }
  base + (if record { ";mode=record" } else { ";mode=play" })
}

///|
pub struct Negotiated {
  transport : Transport
  server_ports : (Int32, Int32)?
  source : String?
  ssrc : String?
}

///|
fn pair(s : String, limit : Int32) -> (Int32, Int32) raise RtspError {
  let parts = s.split("-").to_array()
  require(parts.length() == 2, "transport pair")
  let a = number(parts[0].to_owned(), limit)
  let b = number(parts[1].to_owned(), limit)
  require(b == a + 1, "adjacent RTP RTCP pair")
  (a, b)
}

///|
pub fn negotiate(
  value : String,
  requested : Transport,
) -> Negotiated raise RtspError {
  ignore(requested.encode())
  require(
    value.length() <= 8192 && !value.contains(","),
    "single transport response",
  )
  let segments = value.split(";").to_array()
  let protocol = lower(trim(segments[0].to_owned()))
  let params : Map[String, String] = Map([])
  for i = 1; i < segments.length(); i = i + 1 {
    let xs = trim(segments[i].to_owned()).split("=").to_array()
    let key = lower(xs[0].to_owned())
    require(!params.contains(key), "duplicate transport parameter")
    params[key] = if xs.length() == 1 {
      ""
    } else {
      xs[1:].map(x => x.to_owned()).join("=")
    }
  }
  require(
    params.contains("unicast") && !params.contains("multicast"),
    "unicast transport required",
  )
  match requested {
    Tcp(a, b) => {
      require(protocol == "rtp/avp/tcp", "transport protocol mismatch")
      let selected = match params.get("interleaved") {
        Some(s) => pair(s, 255)
        None => raise Invalid("missing channels")
      }
      require(selected == (a, b), "server changed channels")
    }
    Udp(a, b) => {
      require(
        protocol == "rtp/avp" || protocol == "rtp/avp/udp",
        "UDP protocol mismatch",
      )
      if params.get("client_port") is Some(s) {
        require(pair(s, 65535) == (a, b), "client ports changed")
      }
    }
  }
  let server_ports = match params.get("server_port") {
    Some(s) => Some(pair(s, 65535))
    None => None
  }
  if requested is Udp(_, _) {
    match server_ports {
      Some((a, _)) => require(a > 0, "server UDP port must be positive")
      None => raise Invalid("missing server ports")
    }
  }
  {
    transport: requested,
    server_ports,
    source: params.get("source"),
    ssrc: params.get("ssrc"),
  }
}
