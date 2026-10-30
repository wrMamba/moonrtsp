///|
/// RTP and RTCP are decoded by rtc.mbt; this layer binds packets to RTSP tracks.
pub(all) enum MediaEvent { Rtp(Int, @rtp.Packet); Rtcp(Int, Array[@rtcp.Packet]) }

///|
pub struct ChannelMap { priv channels : Map[Int,(Int,Bool)] }

///|
pub fn ChannelMap::new() -> ChannelMap {{channels:Map([])}}

///|
pub fn ChannelMap::bind(self : ChannelMap, track : Int, transport : Transport) -> Unit raise RtspError {
 require(track>=0 && track<16,"track index")
 match transport {
  Tcp(a,b)=>{
   ignore(transport.encode())
   require(!self.channels.contains(a) && !self.channels.contains(b),"channel collision")
   self.channels[a]=(track,false)
   self.channels[b]=(track,true)
  }
  Udp(_,_)=>raise Invalid("UDP has no interleaved channels")
 }
}

///|
pub fn decode_media(track : Int, control : Bool, bytes : Bytes) -> MediaEvent raise RtspError {
 require(track>=0 && track<16 && bytes.length()<=65535,"media bounds")
 if control {
  let packets=try @rtcp.decode_compound(bytes) catch {_=>raise Invalid("invalid RTCP")}
  Rtcp(track,packets)
 } else {
  let packet=try @rtp.Packet::unmarshal(bytes) catch {_=>raise Invalid("invalid RTP")}
  Rtp(track,packet)
 }
}

///|
pub fn ChannelMap::route(self : ChannelMap, channel : Int, bytes : Bytes) -> MediaEvent raise RtspError {
 match self.channels.get(channel) {Some((track,control))=>decode_media(track,control,bytes);None=>raise Invalid("unnegotiated interleaved channel")}
}

///|
pub struct MediaQueue { priv events : Array[MediaEvent]; priv capacity : Int; priv mut discarded : Int64 }

///|
pub fn MediaQueue::new(capacity? : Int = 256) -> MediaQueue raise RtspError {
 require(capacity>0 && capacity<=4096,"queue capacity")
 {events:[],capacity,discarded:0L}
}

///|
/// Drop oldest on overload to bound latency and memory. Loss is explicit.
pub fn MediaQueue::push(self : MediaQueue, event : MediaEvent) -> Unit {
 if self.events.length()==self.capacity {ignore(self.events.remove(0));self.discarded+=1L}
 self.events.push(event)
}

///|
pub fn MediaQueue::pop(self : MediaQueue) -> MediaEvent? {if self.events.length()==0 {None} else {Some(self.events.remove(0))}}

///|
pub fn MediaQueue::length(self : MediaQueue) -> Int {self.events.length()}

///|
pub fn MediaQueue::discarded(self : MediaQueue) -> Int64 {self.discarded}
