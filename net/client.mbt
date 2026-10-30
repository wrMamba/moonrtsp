///|
/// Socket client. Operations are serialized; cancellation closes the connection.
pub struct Client {
 priv connection : @socket.Tcp
 priv endpoint : @rtsp.Endpoint
 priv session : @rtsp.Session
 priv decoder : @rtsp.Decoder
 priv events : Array[@rtsp.WireEvent]
 priv channels : @rtsp.ChannelMap
 priv queue : @rtsp.MediaQueue
 priv mutex : @async.Mutex
 priv timeout_ms : Int
 priv mut closed : Bool
 priv mut description : @rtsp.Description?
 priv setups : Array[Binding]
 priv stats : Array[@rtsp.TrackStats]
}

///|
priv struct Binding { track : Int; transport : @rtsp.Transport; udp : UdpPair? }

///|
pub async fn Client::connect(uri : String, credentials? : @rtsp.Credentials, cnonce? : String, timeout_ms? : Int = 10000) -> Client {
 if timeout_ms<=0 || timeout_ms>600000 {raise @rtsp.Invalid("connect timeout")}
 let endpoint=@rtsp.Endpoint::parse(uri)
 let auth=match credentials {
  None=>None
  Some(c)=>{let nonce=match cnonce {Some(v)=>v;None=>raise @rtsp.Invalid("credentials require unpredictable cnonce")};Some(@rtsp.Authenticator::new(c,nonce))}
 }
 let session=@rtsp.Session::new(uri,auth?)
 let connection=@async.with_timeout(timeout_ms,()=>@socket.Tcp::connect_to_host(endpoint.hostname().view(),port=endpoint.port))
 errdefer connection.close()
 {connection,endpoint,session,decoder:@rtsp.Decoder::new(),events:[],channels:@rtsp.ChannelMap::new(),queue:@rtsp.MediaQueue::new(),mutex:@async.Mutex(),timeout_ms,closed:false,description:None,setups:[],stats:Array::makei(16,_=>@rtsp.TrackStats::new())}
}

///|
pub fn Client::close(self : Client) -> Unit {
 if !self.closed {
  self.closed=true
  self.connection.close()
  for b in self.setups {if b.udp is Some(pair){pair.close()}}
  self.session.close()
 }
}

///|
pub fn Client::phase(self : Client) -> @rtsp.Phase {self.session.phase()}

///|
pub fn Client::discarded(self : Client) -> Int64 {self.queue.discarded()}

///|
pub fn Client::statistics(self : Client, track : Int) -> @rtsp.StatsSnapshot raise @rtsp.RtspError {
 if track<0 || track>=16 {raise @rtsp.Invalid("statistics track")}
 self.stats[track].snapshot()
}

///|
fn Client::enqueue(self : Client, event : @rtsp.MediaEvent) -> Unit {
 if event is Rtp(track,packet){self.stats[track].observe(packet)}
 self.queue.push(event)
}

///|
async fn Client::next(self : Client) -> @rtsp.WireEvent {
 while self.events.length()==0 {
  let bytes=match self.connection.read_some(max_len=65536){Some(v)=>v;None=>{self.decoder.finish();raise @rtsp.Closed}}
  for event in self.decoder.feed(bytes){self.events.push(event)}
 }
 self.events.remove(0)
}

///|
/// Unsolicited server methods receive a bounded 501 reply; no silent CSeq stealing.
async fn Client::server_command(self : Client, request : @rtsp.Request) -> Unit {
 let headers=@rtsp.Headers::new()
 headers.add("CSeq",request.cseq().to_string())
 let response=@rtsp.Response::new(501,"Not Implemented",headers)
 self.connection.write(response.encode())
}

///|
pub async fn Client::request(self : Client, verb : String, uri? : String, body? : Bytes = b"", headers? : @rtsp.Headers) -> @rtsp.Response {
 self.mutex.acquire()
 defer self.mutex.release()
 if self.closed {raise @rtsp.Closed}
 errdefer self.close()
 @async.with_timeout(self.timeout_ms,()=>{
  let mut req=self.session.request(verb,uri?,body~,headers?,now=@async.now(),timeout_ms=self.timeout_ms)
  self.connection.write(req.encode())
  while true {
   match self.next() {
    Interleaved(channel,data)=>self.enqueue(self.channels.route(channel,data))
    Command(command)=>self.server_command(command)
    Reply(response)=>{
     if response.status<200 {ignore(self.session.accept(response,now=@async.now()));continue}
     match self.session.accept(response,now=@async.now()) {
      Some(retry)=>{req=retry;self.connection.write(req.encode())}
      None=>return response
     }
    }
   }
  } nobreak {raise @rtsp.Closed}
 })
}
