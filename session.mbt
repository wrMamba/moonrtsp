///|
pub(all) enum Phase { Connected; Described; Announced; Ready; Playing; Recording; Paused; Ended } derive(Eq, @debug.Debug)

///|
pub extend Phase with @debug.Debug::{to_repr}

///|
pub extend Phase with Eq::{equal, not_equal}

///|
/// Single outstanding transaction; media can arrive while a response is pending.
pub struct Session {
 priv endpoint : Endpoint
 priv mut serial : Int
 priv mut pending : Request?
 priv mut phase : Phase
 priv mut info : SessionInfo?
 priv auth : Authenticator?
 priv mut attempts : Int
 priv mut deadline : Int64
 priv mut last_activity : Int64
 priv setup_uris : Array[String]
}

///|
pub fn Session::new(uri : String, auth? : Authenticator) -> Session raise RtspError {
 {endpoint: Endpoint::parse(uri), serial:0, pending:None,phase:Connected,info:None,auth,attempts:0,deadline:0L,last_activity:0L,setup_uris:[]}
}

///|
pub fn Session::phase(self : Session) -> Phase {self.phase}

///|
pub fn Session::info(self : Session) -> SessionInfo? {self.info}

///|
pub fn Session::setup_count(self : Session) -> Int {self.setup_uris.length()}

///|
pub fn Session::request(self : Session, verb : String, uri? : String, body? : Bytes = b"", headers? : Headers, now? : Int64 = 0L, timeout_ms? : Int = 10000) -> Request raise RtspError {
 require(self.pending is None && self.phase != Ended,"outstanding transaction or ended session")
 require(timeout_ms>0 && timeout_ms<=600000 && now>=0L && now<=9223372036854175807L,"deadline")
 match verb {
  "DESCRIBE" => require(self.phase==Connected || self.phase==Described,"DESCRIBE phase")
  "ANNOUNCE" => require(self.phase==Connected,"ANNOUNCE phase")
  "SETUP" => require(self.phase==Described || self.phase==Announced || self.phase==Ready,"SETUP phase")
  "PLAY" => require((self.phase==Ready || self.phase==Paused) && self.setup_uris.length()>0,"PLAY phase")
  "RECORD" => require(self.phase==Ready && self.setup_uris.length()>0,"RECORD phase")
  "PAUSE" => require(self.phase==Playing || self.phase==Recording,"PAUSE phase")
  "TEARDOWN" | "OPTIONS" | "GET_PARAMETER" | "SET_PARAMETER" => ()
  _ => raise Invalid("unsupported client method")
 }
 require(self.serial<2147483647,"CSeq exhausted")
 let target = uri.unwrap_or(self.endpoint.url())
 self.serial+=1
 let req = Request::new(verb,target,self.serial,body~)
 if headers is Some(extra) {
  for (k,v) in extra.items() {require(lower(k)!="cseq" && lower(k)!="session" && lower(k)!="authorization" && lower(k)!="content-length","reserved request header"); req.headers.add(k,v)}
 }
 if self.info is Some(info) {req.headers.set("Session",info.id)}
 if self.auth is Some(a) {if a.challenge!="" {req.headers.set("Authorization",a.authorization(verb,target))}}
 self.pending=Some(req)
 self.deadline=now+timeout_ms.to_int64()
 self.attempts=0
 req
}

///|
/// Returns a retry request only for a validated authentication challenge.
pub fn Session::accept(self : Session, response : Response, now? : Int64 = 0L) -> Request? raise RtspError {
 let request = match self.pending {Some(r)=>r;None=>raise State("unsolicited reply")}
 require(response.cseq()==request.cseq(),"CSeq mismatch")
 require(now>=0L,"negative time")
 if response.status<200 {return None}
 if response.status==401 && self.attempts<2 {
  if self.auth is Some(auth) {
   let challenges=response.headers.all("WWW-Authenticate")
   require(challenges.length()>0,"missing challenge")
   let mut chosen=challenges[0]
   for c in challenges {if c.has_prefix("Digest "){chosen=c;break}}
   auth.challenge(chosen)
   require(self.serial<2147483647,"CSeq exhausted")
   self.serial+=1
   let retry=Request::new(request.verb,request.uri,self.serial,body=request.body)
   for (k,v) in request.headers.items() {if lower(k)!="cseq" && lower(k)!="authorization" {retry.headers.set(k,v)}}
   retry.headers.set("Authorization",auth.authorization(request.verb,request.uri))
   self.attempts+=1
   self.pending=Some(retry)
   return Some(retry)
  }
 }
 self.pending=None
 self.last_activity=now
 if response.status<200 || response.status>=300 {raise Remote(response.status)}
 if response.headers.unique("Session") is Some(value) {
  let info=parse_session(value)
  if self.info is Some(old) {require(old.id==info.id,"session identity changed")}
  self.info=Some(info)
 }
 match request.verb {
  "DESCRIBE"=>self.phase=Described
  "ANNOUNCE"=>self.phase=Announced
  "SETUP"=>{require(self.info is Some(_),"SETUP missing Session"); if !self.setup_uris.contains(request.uri){require(self.setup_uris.length()<16,"setup track limit");self.setup_uris.push(request.uri)};self.phase=Ready}
  "PLAY"=>self.phase=Playing
  "RECORD"=>self.phase=Recording
  "PAUSE"=>self.phase=Paused
  "TEARDOWN"=>{self.phase=Ended;self.info=None}
  _=>()
 }
 None
}

///|
pub fn Session::check_deadline(self : Session, now : Int64) -> Unit raise RtspError {
 if self.pending is Some(_) && now>=self.deadline {self.pending=None;self.phase=Ended;raise State("transaction timed out; reconnect required")}
}

///|
pub fn Session::keepalive_due(self : Session, now : Int64) -> Bool {
 match self.info {Some(info)=> self.pending is None && self.phase!=Ended && now-self.last_activity >= info.timeout_seconds.to_int64()*500L;None=>false}
}

///|
pub fn Session::close(self : Session) -> Unit {self.pending=None;self.phase=Ended;self.info=None}
