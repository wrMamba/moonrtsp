///|
pub struct Request { verb : String; uri : String; headers : Headers; body : Bytes }

///|
pub struct Response { status : Int; reason : String; headers : Headers; body : Bytes }

///|
pub fn Request::new(verb : String, uri : String, cseq : Int, body? : Bytes = b"") -> Request raise RtspError {
 require(verb.length() > 0 && verb.length() <= 32, "verb length")
 for c in verb { require((c >= 'A' && c <= 'Z') || c == '_', "verb token") }
 ignore(Endpoint::parse(uri))
 require(cseq > 0, "positive CSeq")
 require(body.length() <= 1048576, "body limit")
 let headers = Headers::new()
 headers.add("CSeq", cseq.to_string())
 headers.add("User-Agent", "MoonRTSP/0.1.0")
 { verb, uri, headers, body }
}

///|
pub fn Request::encode(self : Request) -> Bytes raise RtspError {
 // Revalidate public fields and headers at serialization boundary.
 ignore(Request::new(self.verb, self.uri, self.cseq(), body=self.body))
 let headers = self.headers.copy()
 if self.body.length() > 0 { headers.set("Content-Length", self.body.length().to_string()) }
 else { headers.set("Content-Length", "0") }
 octets(self.verb + " " + self.uri + " RTSP/1.0\r\n" + headers.wire() + "\r\n") + self.body
}

///|
pub fn Request::cseq(self : Request) -> Int raise RtspError {
 match self.headers.unique("CSeq") { Some(v) => number(v, 2147483647); None => raise Invalid("missing CSeq") }
}

///|
pub fn Response::cseq(self : Response) -> Int raise RtspError {
 match self.headers.unique("CSeq") { Some(v) => number(v, 2147483647); None => raise Invalid("missing CSeq") }
}

///|
pub fn Response::encode(self : Response) -> Bytes raise RtspError {
 require(self.status >= 100 && self.status <= 599 && clean(self.reason), "response status")
 require(self.body.length() <= 1048576, "body limit")
 let h = self.headers.copy()
 h.set("Content-Length", self.body.length().to_string())
 octets("RTSP/1.0 " + self.status.to_string() + " " + self.reason + "\r\n" + h.wire() + "\r\n") + self.body
}

///|
fn parse_head(data : Bytes) -> (String, Headers, Int) raise RtspError {
 let text = bytes_text(data)
 let lines = text.split("\r\n").to_array()
 require(lines.length() >= 3, "incomplete header")
 let headers = Headers::new()
 for i = 1; i < lines.length()-2; i = i + 1 {
  let line = lines[i].to_owned()
  let parts = line.split(":").to_array()
  require(parts.length() >= 2, "header separator")
  headers.add(parts[0].to_owned(), parts[1:].map(x => x.to_owned()).join(":"))
 }
 ignore(headers.unique("CSeq"))
 ignore(headers.unique("Session"))
 require(headers.get("Transfer-Encoding") is None, "transfer encoding unsupported")
 let length = match headers.unique("Content-Length") { Some(s) => number(s, 1048576); None => 0 }
 (lines[0].to_owned(), headers, length)
}

///|
fn response_from_head(start : String, headers : Headers, body : Bytes) -> Response raise RtspError {
 let parts = start.split(" ").to_array()
 require(parts.length() >= 3 && parts[0] == "RTSP/1.0", "response start line")
 let status = number(parts[1].to_owned(), 599)
 require(status >= 100, "response status")
 { status, reason: parts[2:].map(x => x.to_owned()).join(" "), headers, body }
}

///|
fn request_from_head(start : String, headers : Headers, body : Bytes) -> Request raise RtspError {
 let parts = start.split(" ").to_array()
 require(parts.length() == 3 && parts[2] == "RTSP/1.0", "request start line")
 let r = Request::{ verb: parts[0].to_owned(), uri: parts[1].to_owned(), headers, body }
 ignore(Request::new(r.verb, r.uri, r.cseq(), body~))
 r
}

///|
pub fn Response::new(status : Int, reason : String, headers : Headers, body? : Bytes = b"") -> Response raise RtspError {
 let response={status,reason,headers:headers.copy(),body}
 ignore(response.encode())
 response
}
