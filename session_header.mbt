///|
pub struct SessionInfo { id : String; timeout_seconds : Int }

///|
pub fn parse_session(value : String) -> SessionInfo raise RtspError {
 let parts = value.split(";").to_array()
 let id = trim(parts[0].to_owned())
 require(id.length() > 0 && id.length() <= 256 && clean(id) && !id.contains(" "), "session id")
 let mut timeout_seconds = 60
 let mut found = false
 for i = 1; i < parts.length(); i = i+1 {
  let p = parts[i].split("=").to_array()
  if lower(trim(p[0].to_owned())) == "timeout" {
   require(!found && p.length() == 2, "session timeout")
   timeout_seconds = number(trim(p[1].to_owned()),86400)
   require(timeout_seconds > 0, "zero timeout")
   found = true
  }
 }
 { id, timeout_seconds }
}

///|
pub struct RtpInfo { url : String; sequence : Int?; timestamp : UInt? }

///|
pub fn parse_rtp_info(value : String, base : String) -> Array[RtpInfo] raise RtspError {
 require(value.length() <= 8192, "RTP-Info length")
 let result = []
 for item in value.split(",") {
  require(result.length() < 16, "RTP-Info count")
  let fields : Map[String,String] = Map([])
  for field in item.split(";") {
   let p = field.split("=").to_array()
   require(p.length() >= 2, "RTP-Info field")
   let k = lower(trim(p[0].to_owned()))
   require(!fields.contains(k), "duplicate RTP-Info field")
   fields[k] = trim(p[1:].map(x => x.to_owned()).join("="))
  }
  let url = match fields.get("url") { Some(v) => resolve_control(base,v); None => raise Invalid("RTP-Info url") }
  let sequence = fields.get("seq").map(v => number(v,65535))
  let timestamp = match fields.get("rtptime") {
   None => None
   Some(v) => {
    require(v.length()>0 && v.length()<=10, "rtptime length")
    let mut n = 0UL
    for c in v { require(c>='0' && c<='9', "rtptime digit"); n = n*10UL+(c.to_int()-48).to_uint64(); require(n<=4294967295UL,"rtptime overflow") }
    Some(n.to_uint())
   }
  }
  result.push({url,sequence,timestamp})
 }
 result
}
