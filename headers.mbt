///|
/// A bounded ordered header collection. Names compare without ASCII case.
pub struct Headers {
  priv entries : Array[(String, String)]
}

///|
pub fn Headers::new() -> Headers {
  { entries: [], }
}

///|
pub fn Headers::add(
  self : Headers,
  name : String,
  value : String,
) -> Unit raise RtspError {
  require(self.entries.length() < 128, "header count")
  require(name.length() > 0 && name.length() <= 128, "header name length")
  for c in name {
    require(
      (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '-' ||
      c == '_',
      "header name",
    )
  }
  require(value.length() <= 8192 && clean(value), "header value")
  self.entries.push((name, trim(value)))
}

///|
pub fn Headers::get(self : Headers, name : String) -> String? {
  let key = lower(name)
  for (k, v) in self.entries {
    if lower(k) == key {
      return Some(v)
    }
  }
  None
}

///|
pub fn Headers::all(self : Headers, name : String) -> Array[String] {
  let values = []
  for (k, v) in self.entries {
    if lower(k) == lower(name) {
      values.push(v)
    }
  }
  values
}

///|
pub fn Headers::set(
  self : Headers,
  name : String,
  value : String,
) -> Unit raise RtspError {
  let validated = Headers::new()
  validated.add(name, value)
  let mut i = self.entries.length() - 1
  while i >= 0 {
    if lower(self.entries[i].0) == lower(name) {
      self.entries.remove(i) |> ignore
    }
    i -= 1
  }
  self.add(name, value)
}

///|
pub fn Headers::items(self : Headers) -> Array[(String, String)] {
  self.entries.copy()
}

///|
pub fn Headers::copy(self : Headers) -> Headers {
  { entries: self.entries.copy(), }
}

///|
fn Headers::wire(self : Headers) -> String {
  let out = StringBuilder()
  for (k, v) in self.entries {
    out.write_string(k + ": " + v + "\r\n")
  }
  out.to_string()
}

///|
fn Headers::unique(self : Headers, name : String) -> String? raise RtspError {
  let values = self.all(name)
  require(values.length() <= 1, "duplicate framing header")
  if values.length() == 0 {
    None
  } else {
    Some(values[0])
  }
}
