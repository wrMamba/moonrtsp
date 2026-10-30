///|
/// RTSP track selection uses the existing SDP parser rather than implementing another SDP language.
pub struct Track {
  index : Int32
  kind : String
  control : String
  formats : Array[String]
  rtpmap : Array[String]
  fmtp : Array[String]
}

///|
pub struct Description {
  aggregate : String
  tracks : Array[Track]
  raw : String
}

///|
pub fn describe(body : Bytes, base : String) -> Description raise RtspError {
  require(body.length() <= 1048576, "SDP limit")
  let raw = bytes_text(body)
  let document = match @sdp.parse(raw) {
    Ok(d) => d
    Err(_) => raise Invalid("SDP parse failed")
  }
  let mut aggregate = base
  for attr in document.attributes() {
    if attr.name() == "control" {
      if attr.value() is Some(v) {
        aggregate = resolve_control(base, v)
      }
    }
  }
  let tracks = []
  for media in document.media_descriptions() {
    require(tracks.length() < 16, "track count")
    let control = match media.attribute_value("control") {
      Some(v) => resolve_control(base, v)
      None => raise Invalid("track missing control")
    }
    let rtpmap = []
    let fmtp = []
    for a in media.attributes() {
      if a.value() is Some(v) {
        if a.name() == "rtpmap" {
          rtpmap.push(v)
        }
        if a.name() == "fmtp" {
          fmtp.push(v)
        }
      }
    }
    tracks.push({
      index: tracks.length(),
      kind: media.media(),
      control,
      formats: media.formats().copy(),
      rtpmap,
      fmtp,
    })
  }
  require(tracks.length() > 0, "no media tracks")
  { aggregate, tracks, raw, }
}

///|
pub fn Description::select(
  self : Description,
  indices : Array[Int32],
) -> Array[Track] raise RtspError {
  require(
    indices.length() > 0 && indices.length() <= self.tracks.length(),
    "track selection",
  )
  let selected = []
  let seen : Set[Int32] = Set([])
  for i in indices {
    require(
      i >= 0 && i < self.tracks.length() && !seen.contains(i),
      "track index",
    )
    seen.add(i)
    selected.push(self.tracks[i])
  }
  selected
}
