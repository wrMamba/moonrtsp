///|
/// Bounded exponential backoff, independent of wall-clock jitter sources.
pub struct ReconnectPolicy {
  attempts : Int32
  initial_ms : Int32
  maximum_ms : Int32
}

///|
pub fn ReconnectPolicy::new(
  attempts~ : Int32 = 3,
  initial_ms~ : Int32 = 250,
  maximum_ms~ : Int32 = 10000,
) -> ReconnectPolicy raise RtspError {
  require(
    attempts >= 0 &&
    attempts <= 20 &&
    initial_ms > 0 &&
    maximum_ms >= initial_ms &&
    maximum_ms <= 600000,
    "reconnect policy",
  )
  { attempts, initial_ms, maximum_ms, }
}

///|
pub fn ReconnectPolicy::delay(
  self : ReconnectPolicy,
  attempt : Int32,
) -> Int32 raise RtspError {
  require(
    attempt >= 0 && attempt < self.attempts,
    "reconnect attempts exhausted",
  )
  let mut delay = self.initial_ms
  for _i = 0; _i < attempt; _i = _i + 1 {
    delay = if delay > self.maximum_ms / 2 {
      self.maximum_ms
    } else {
      delay * 2
    }
  }
  delay
}
