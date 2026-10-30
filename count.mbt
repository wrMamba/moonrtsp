///|
/// Strict decimal CLI/config parser; no signs, whitespace, overflow or silent defaults.
pub fn parse_count(text : String, maximum : Int32) -> Int32 raise RtspError {
  require(maximum > 0, "count limit")
  let n = number(text, maximum)
  require(n > 0, "positive count")
  n
}
