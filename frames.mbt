///|
pub struct Frame { timestamp : UInt; data : Bytes; packets : Int }

///|
/// Consecutive, same-source RTP access units. Any gap invalidates the whole frame.
pub struct FrameAssembler {
 priv codec : @rtp.PayloadCodec
 priv max_bytes : Int
 priv max_packets : Int
 priv chunks : Array[Bytes]
 priv mut timestamp : UInt?
 priv mut source : UInt?
 priv mut expected : Int?
 priv mut size : Int
 priv mut broken : Bool
}

///|
pub fn FrameAssembler::new(codec : @rtp.PayloadCodec, max_bytes? : Int = 4194304, max_packets? : Int = 4096) -> FrameAssembler raise RtspError {
 require(max_bytes>0 && max_bytes<=16777216 && max_packets>0 && max_packets<=16384,"frame limits")
 {codec,max_bytes,max_packets,chunks:[],timestamp:None,source:None,expected:None,size:0,broken:false}
}

///|
pub fn FrameAssembler::reset(self : FrameAssembler) -> Unit {
 self.chunks.clear();self.timestamp=None;self.source=None;self.expected=None;self.size=0;self.broken=false
}

///|
pub fn FrameAssembler::push(self : FrameAssembler, packet : @rtp.Packet) -> Frame? raise RtspError {
 let changed=self.timestamp!=Some(packet.timestamp()) || self.source!=Some(packet.ssrc())
 if changed {
  self.chunks.clear();self.size=0;self.broken=false
  self.timestamp=Some(packet.timestamp());self.source=Some(packet.ssrc())
  if !self.codec.is_partition_head(packet.payload()) {self.broken=true}
 }
 if self.expected is Some(sequence) {if sequence!=packet.sequence_number().to_int() {self.broken=true}}
 self.expected=Some((packet.sequence_number().to_int()+1)%65536)
 if packet.payload().length()>self.max_bytes-self.size || self.chunks.length()>=self.max_packets {
  self.chunks.clear();self.broken=true;raise Limit("frame budget")
 }
 if !self.broken {self.chunks.push(packet.payload());self.size+=packet.payload().length()}
 if !packet.marker() {return None}
 if self.broken {self.chunks.clear();self.size=0;return None}
 let data=try @rtp.depacketize_payload(self.codec,self.chunks) catch {_=>{self.chunks.clear();self.size=0;raise Invalid("codec payload")}}
 let frame={timestamp:packet.timestamp(),data,packets:self.chunks.length()}
 self.chunks.clear();self.size=0
 Some(frame)
}
