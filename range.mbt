///|
pub(all) enum PlayRange {
  Live
  FromMillis(Int64)
  Interval(Int64, Int64)
}

///|
fn millis_text(value : Int64) -> String raise RtspError {
  require(value >= 0L && value <= 86400000000L, "NPT range")
  let whole = (value / 1000L).to_string()
  let fraction = (value % 1000L).to_int()
  let tail = if fraction < 10 {
    "00"
  } else if fraction < 100 {
    "0"
  } else {
    ""
  }
  whole + "." + tail + fraction.to_string()
}

///|
pub fn PlayRange::encode(self : PlayRange) -> String raise RtspError {
  match self {
    Live => "npt=now-"
    FromMillis(n) => "npt=" + millis_text(n) + "-"
    Interval(a, b) => {
      require(b >= a, "NPT end precedes start")
      "npt=" + millis_text(a) + "-" + millis_text(b)
    }
  }
}

///|
pub fn parse_public(headers : Headers) -> Array[String] raise RtspError {
  let result = []
  for field in headers.all("Public") {
    for item in field.split(",") {
      let verb = trim(item.to_owned())
      require(verb.length() > 0 && verb.length() <= 32, "Public method")
      for c in verb {
        require((c >= 'A' && c <= 'Z') || c == '_', "Public method characters")
      }
      if !result.contains(verb) {
        result.push(verb)
      }
    }
  }
  result
}
