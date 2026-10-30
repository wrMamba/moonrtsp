///|
pub struct Credentials { priv user : String; priv password : String }

///|
pub fn Credentials::new(user : String, password : String) -> Credentials raise RtspError {
 require(user.length() > 0 && user.length() <= 256 && password.length() <= 1024, "credential length")
 require(clean(user) && clean(password) && !user.contains(":"), "credential characters")
 { user, password }
}

///|
pub struct Authenticator { priv credentials : Credentials; priv mut challenge : String; priv mut count : Int; priv cnonce : String }

///|
/// Caller supplies an unpredictable cnonce for production Digest qop=auth.
pub fn Authenticator::new(credentials : Credentials, cnonce : String) -> Authenticator raise RtspError {
 require(cnonce.length() >= 8 && cnonce.length() <= 128 && clean(cnonce), "cnonce")
 { credentials, challenge: "", count: 0, cnonce }
}

///|
pub fn Authenticator::challenge(self : Authenticator, header : String) -> Unit raise RtspError {
 require(header.has_prefix("Basic ") || header.has_prefix("Digest "), "authentication scheme")
 let offset = if header.has_prefix("Basic ") { 6 } else { 7 }
 let params = parse_parameters(header[offset:].to_owned())
 if offset == 7 {
  require(params.contains("realm") && params.contains("nonce"), "Digest realm and nonce")
  require(params.get("algorithm").unwrap_or("MD5") == "MD5", "Digest algorithm unsupported")
  if params.get("qop") is Some(qop) {
   require(qop.split(",").any(x => trim(x.to_owned()) == "auth"), "Digest qop unsupported")
  }
 }
 if header != self.challenge { self.count = 0 }
 self.challenge = header
}

///|
fn md5_hex(s : String) -> String {
 let digest = @md5.Digest::new()
 for b in octets(s) { digest.write(b) }
 digest.check_sum()
}

///|
fn hex_count(n : Int) -> String {
 let digits = "0123456789abcdef"
 let out = StringBuilder()
 for i = 7; i >= 0; i = i-1 { let j = (n >> (i*4)) & 15; out.write_string(digits[j:j+1].to_owned()) }
 out.to_string()
}

///|
pub fn Authenticator::authorization(self : Authenticator, verb : String, uri : String) -> String raise RtspError {
 require(self.challenge != "", "missing challenge")
 let user = self.credentials.user
 let password = self.credentials.password
 if self.challenge.has_prefix("Basic ") { return "Basic " + @base64.encode(octets(user+":"+password)) }
 let p = parse_parameters(self.challenge[7:].to_owned())
 let realm = p["realm"]
 let nonce = p["nonce"]
 require(self.count < 2147483647, "Digest nonce count exhausted")
 self.count += 1
 let nc = hex_count(self.count)
 let has_qop = p.contains("qop")
 let middle = if has_qop { nonce+":"+nc+":"+self.cnonce+":auth" } else { nonce }
 let response = md5_hex(md5_hex(user+":"+realm+":"+password)+":"+middle+":"+md5_hex(verb+":"+uri))
 let mut result = "Digest username="+quoted(user)+", realm="+quoted(realm)+", nonce="+quoted(nonce)+", uri="+quoted(uri)+", response="+quoted(response)+", algorithm=MD5"
 if has_qop { result += ", qop=auth, nc="+nc+", cnonce="+quoted(self.cnonce) }
 if p.get("opaque") is Some(v) { result += ", opaque="+quoted(v) }
 result
}
