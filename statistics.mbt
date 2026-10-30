///|
pub struct StatsSnapshot {
  packets : Int64
  octets : Int64
  forward_gaps : Int64
  late_or_duplicate : Int64
  source_changes : Int64
}

///|
pub struct TrackStats {
  priv mut previous : Int32?
  priv mut source : UInt32?
  priv mut packets_mut : Int64
  priv mut octets_mut : Int64
  priv mut gaps_mut : Int64
  priv mut late_mut : Int64
  priv mut changes_mut : Int64
}

///|
pub fn TrackStats::new() -> TrackStats {
  {
    previous: None,
    source: None,
    packets_mut: 0L,
    octets_mut: 0L,
    gaps_mut: 0L,
    late_mut: 0L,
    changes_mut: 0L,
  }
}

///|
/// Forward gaps are observed sequence gaps, not a network loss estimate.
pub fn TrackStats::observe(self : TrackStats, packet : @rtp.Packet) -> Unit {
  let sequence = packet.sequence_number().to_int()
  if self.source is Some(old) {
    if old != packet.ssrc() {
      self.previous = None
      self.changes_mut += 1L
    }
  }
  self.source = Some(packet.ssrc())
  if self.previous is Some(old) {
    let delta = (sequence - old + 65536) % 65536
    if delta > 0 && delta < 32768 {
      self.gaps_mut += (delta - 1).to_int64()
      self.previous = Some(sequence)
    } else {
      self.late_mut += 1L
    }
  } else {
    self.previous = Some(sequence)
  }
  self.packets_mut += 1L
  self.octets_mut += packet.payload().length().to_int64()
}

///|
pub fn TrackStats::snapshot(self : TrackStats) -> StatsSnapshot {
  {
    packets: self.packets_mut,
    octets: self.octets_mut,
    forward_gaps: self.gaps_mut,
    late_or_duplicate: self.late_mut,
    source_changes: self.changes_mut,
  }
}

///|
/// Extend an RTP timestamp across wraps; backward values remain backward.
pub struct Clock {
  priv rate : Int32
  priv mut anchor : UInt32?
  priv mut ticks : Int64
}

///|
pub fn Clock::new(rate : Int32) -> Clock raise RtspError {
  require(rate > 0 && rate <= 1000000000, "clock rate")
  { rate, anchor: None, ticks: 0L, }
}

///|
pub fn Clock::millis(self : Clock, timestamp : UInt32) -> Int64 {
  if self.anchor is Some(previous) {
    let delta = (timestamp - previous).reinterpret_as_int().to_int64()
    self.ticks += delta
  }
  self.anchor = Some(timestamp)
  self.ticks / self.rate.to_int64() * 1000L +
  self.ticks % self.rate.to_int64() * 1000L / self.rate.to_int64()
}
