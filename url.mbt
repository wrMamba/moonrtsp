///|
/// An RTSP endpoint without embedded credentials. Paths retain their escaping.
pub struct Endpoint { host : String; port : Int; path : String }

///|
pub fn Endpoint::parse(input : String) -> Endpoint raise RtspError {
 require(input.length() <= 8192 && clean(input), "URL length or characters")
 require(input.has_prefix("rtsp://"), "only rtsp scheme supported")
 let tail = input[7:].to_owned()
 require(!tail.contains("@") && !tail.contains("#") && !tail.contains(" "), "URL credentials, fragment or spaces")
 let parts = tail.split("/").to_array()
 let authority = parts[0].to_owned()
 require(authority.length() > 0 && !authority.contains("?"), "URL authority")
 let mut host = ""
 let mut port = 554
 if authority.has_prefix("[") {
  let a = authority.split("]").to_array()
  require(a.length() == 2, "IPv6 URL")
  host = a[0].to_owned() + "]"
  let rest = a[1].to_owned()
  port = if rest == "" { 554 } else { require(rest.has_prefix(":"), "URL port separator"); number(rest[1:].to_owned(), 65535) }
 } else {
  let a = authority.split(":").to_array()
  require(a.length() <= 2, "bracket IPv6 literal")
  host = a[0].to_owned()
  port = if a.length() == 1 { 554 } else { number(a[1].to_owned(), 65535) }
 }
 require(host.length() > 0 && port > 0, "URL host or port")
 let path = if parts.length() == 1 { "/" } else { "/" + parts[1:].map(x => x.to_owned()).join("/") }
 { host, port, path }
}

///|
pub fn Endpoint::url(self : Endpoint) -> String {
 "rtsp://" + self.host + (if self.port == 554 { "" } else { ":" + self.port.to_string() }) + self.path
}

///|
pub fn Endpoint::hostname(self : Endpoint) -> String {
 if self.host.has_prefix("[") { self.host[1:self.host.length()-1].to_owned() } else { self.host }
}

///|
pub fn resolve_control(base : String, control : String) -> String raise RtspError {
 let endpoint = Endpoint::parse(base)
 require(control.length() > 0 && clean(control), "control URL")
 if control == "*" { return endpoint.url() }
 if control.has_prefix("rtsp://") { return Endpoint::parse(control).url() }
 require(!control.contains("://") && !control.contains("#") && !control.contains(" "), "control scheme or characters")
 if control.has_prefix("/") {
  return Endpoint::{ host: endpoint.host, port: endpoint.port, path: control }.url()
 }
 let path = endpoint.path.split("?").to_array()[0].to_owned()
 let parts = path.split("/").to_array().map(x => x.to_owned())
 ignore(parts.pop())
 for segment in control.split("/") {
  match segment { ".." => { if parts.length() > 1 { ignore(parts.pop()) } }; "." => (); _ => parts.push(segment.to_owned()) }
 }
 Endpoint::{ host: endpoint.host, port: endpoint.port, path: parts.join("/") }.url()
}

