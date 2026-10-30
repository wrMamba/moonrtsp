///|
pub(all) suberror RtspError {
  Invalid(String)
  Limit(String)
  State(String)
  Remote(Int32)
  Closed
} derive(@debug.Debug)

///|
fn require(ok : Bool, message : String) -> Unit raise RtspError {
  if !ok {
    raise Invalid(message)
  }
}

///|
fn number(s : String, maximum : Int32) -> Int32 raise RtspError {
  require(s.length() > 0 && s.length() <= 10, "decimal length")
  let mut n = 0
  for c in s {
    require(c >= '0' && c <= '9', "decimal digit")
    let digit = c.to_int() - 48
    require(n <= (maximum - digit) / 10 && digit <= maximum, "decimal range")
    n = n * 10 + digit
  }
  n
}

///|
fn clean(s : String) -> Bool {
  for c in s {
    if c.to_int() < 32 || c.to_int() > 126 {
      return false
    }
  }
  true
}

///|
fn trim(s : String) -> String {
  s.trim().to_owned()
}

///|
fn lower(s : String) -> String {
  s.to_lower()
}

///|
fn bytes_text(b : Bytes) -> String raise RtspError {
  @utf8.decode(b) catch {
    _ => raise Invalid("invalid UTF-8")
  }
}

///|
fn octets(s : String) -> Bytes {
  @utf8.encode(s)
}

///|
pub extend RtspError with @debug.Debug::{to_repr}
