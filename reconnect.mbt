///|
/// Bounded exponential backoff, independent of wall-clock jitter sources.
pub struct ReconnectPolicy { attempts : Int; initial_ms : Int; maximum_ms : Int }

///|
pub fn ReconnectPolicy::new(attempts? : Int = 3, initial_ms? : Int = 250, maximum_ms? : Int = 10000) -> ReconnectPolicy raise RtspError {
 require(attempts>=0 && attempts<=20 && initial_ms>0 && maximum_ms>=initial_ms && maximum_ms<=600000,"reconnect policy")
 {attempts,initial_ms,maximum_ms}
}

///|
pub fn ReconnectPolicy::delay(self : ReconnectPolicy, attempt : Int) -> Int raise RtspError {
 require(attempt>=0 && attempt<self.attempts,"reconnect attempts exhausted")
 let mut delay=self.initial_ms
 for _i=0;_i<attempt;_i=_i+1 {delay=if delay>self.maximum_ms/2 {self.maximum_ms} else {delay*2}}
 delay
}
