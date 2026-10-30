///|
pub(all) enum WireEvent {
  Reply(Response)
  Command(Request)
  Interleaved(Int32, Bytes)
}

///|
/// Incremental decoder with fixed limits. A fatal parse error poisons it until reset.
pub struct Decoder {
  priv mut buffer : Bytes
  priv mut failed : Bool
  priv max_buffer : Int32
}

///|
pub fn Decoder::new(max_buffer~ : Int32 = 2097152) -> Decoder raise RtspError {
  require(max_buffer >= 65540 && max_buffer <= 8388608, "decoder limit")
  { buffer: b"", failed: false, max_buffer, }
}

///|
pub fn Decoder::reset(self : Decoder) -> Unit {
  self.buffer = b""
  self.failed = false
}

///|
pub fn Decoder::pending(self : Decoder) -> Int32 {
  self.buffer.length()
}

///|
pub fn Decoder::feed(
  self : Decoder,
  chunk : Bytes,
) -> Array[WireEvent] raise RtspError {
  if self.failed {
    raise State("decoder needs reset")
  }
  errdefer {
    self.failed = true
    self.buffer = b""
  }
  if chunk.length() > self.max_buffer - self.buffer.length() {
    raise Limit("receive buffer")
  }
  self.buffer = self.buffer + chunk
  let events = []
  while self.buffer.length() > 0 {
    let input = self.buffer
    if input[0] == b'\x24' {
      if input.length() < 4 {
        break
      }
      let size = input[2].to_int() * 256 + input[3].to_int()
      if input.length() < size + 4 {
        break
      }
      events.push(Interleaved(input[1].to_int(), input[4:4 + size].to_owned()))
      self.buffer = input[4 + size:].to_owned()
    } else {
      let mut end = -1
      for i = 0; i + 3 < input.length() && i < 32768; i = i + 1 {
        if input[i] == b'\r' &&
          input[i + 1] == b'\n' &&
          input[i + 2] == b'\r' &&
          input[i + 3] == b'\n' {
          end = i + 4
          break
        }
      }
      if end < 0 {
        if input.length() >= 32768 {
          raise Limit("header bytes")
        }
        break
      }
      let (start, headers, size) = parse_head(input[:end].to_owned())
      if input.length() < end + size {
        break
      }
      let body = input[end:end + size].to_owned()
      if start.has_prefix("RTSP/") {
        events.push(Reply(response_from_head(start, headers, body)))
      } else {
        events.push(Command(request_from_head(start, headers, body)))
      }
      self.buffer = input[end + size:].to_owned()
    }
  }
  events
}

///|
pub fn interleave(channel : Int32, packet : Bytes) -> Bytes raise RtspError {
  require(
    channel >= 0 && channel <= 255 && packet.length() <= 65535,
    "interleaved channel or length",
  )
  Bytes::from_array([
    b'\x24',
    channel.to_byte(),
    (packet.length() / 256).to_byte(),
    (packet.length() % 256).to_byte(),
  ]) +
  packet
}

///|
pub fn Decoder::finish(self : Decoder) -> Unit raise RtspError {
  if self.failed {
    raise State("decoder failed")
  }
  if self.pending() != 0 {
    self.failed = true
    raise Invalid("truncated stream")
  }
}
