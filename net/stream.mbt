///|
pub async fn Client::receive(self : Client) -> @rtsp.MediaEvent {
  self.mutex.acquire()
  defer self.mutex.release()
  if self.closed {
    raise @rtsp.Closed
  }
  errdefer self.close()
  @async.with_timeout(self.timeout_ms, () => {
    while true {
      if self.queue.pop() is Some(event) {
        return event
      }
      match self.next() {
        Interleaved(channel, data) =>
          self.enqueue(self.channels.route(channel, data))
        Command(request) => self.server_command(request)
        Reply(_) => raise @rtsp.Invalid("unsolicited RTSP reply")
      }
    } nobreak {
      raise @rtsp.Closed
    }
  })
}

///|
pub async fn Client::receive_udp(
  self : Client,
  track : Int32,
  control~ : Bool = false,
) -> @rtsp.MediaEvent {
  if self.closed {
    raise @rtsp.Closed
  }
  for b in self.setups {
    if b.track == track {
      let pair = match b.udp {
        Some(p) => p
        None => raise @rtsp.State("track is TCP")
      }
      let bytes = @async.with_timeout(self.timeout_ms, () => {
        pair.receive(control)
      })
      let event = @rtsp.decode_media(track, control, bytes)
      if event is Rtp(index, packet) {
        self.stats[index].observe(packet)
      }
      return event
    }
  }
  raise @rtsp.Invalid("track not setup")
}

///|
/// Publishing accepts complete RTP/RTCP packets and preserves their clocks and SSRC.
pub async fn Client::send(
  self : Client,
  track : Int32,
  bytes : Bytes,
  control~ : Bool = false,
) -> Unit {
  if self.closed || self.session.phase() != @rtsp.Recording {
    raise @rtsp.State("not recording")
  }
  ignore(@rtsp.decode_media(track, control, bytes))
  for b in self.setups {
    if b.track == track {
      match b.transport {
        Tcp(a, c) => {
          self.mutex.acquire()
          defer self.mutex.release()
          errdefer self.close()
          @async.with_timeout(self.timeout_ms, () => {
            self.connection.write(
              @rtsp.interleave(if control { c } else { a }, bytes),
            )
          })
        }
        Udp(_, _) =>
          match b.udp {
            Some(pair) =>
              @async.with_timeout(self.timeout_ms, () => {
                pair.send(control, bytes)
              })
            None => raise @rtsp.State("missing UDP sockets")
          }
      }
      return
    }
  }
  raise @rtsp.Invalid("track not setup")
}

///|
pub async fn Client::send_packet(
  self : Client,
  track : Int32,
  packet : @rtp.Packet,
) -> Unit {
  self.send(track, packet.marshal())
}
