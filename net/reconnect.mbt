///|
/// Reconnect creates a fresh server session and repeats track negotiation.
/// The callback runs once per successful connection; it may finish or raise.
/// Cancellation propagates; it is never retried by this helper.
pub async fn follow(uri : String, indices : Array[Int], policy : @rtsp.ReconnectPolicy, on_connected : async (Client) -> Unit, udp? : Bool = false, credentials? : @rtsp.Credentials, cnonce? : String) -> Unit {
 let mut attempt=0
 while true {
  try {
   let client=Client::connect(uri,credentials?,cnonce?)
   defer client.close()
   let description=client.describe()
   ignore(description.select(indices))
   for index in indices {ignore(client.setup(index,udp~))}
   ignore(client.play())
   on_connected(client)
   return
  } catch {
   error=>{
    if @async.is_being_cancelled() || attempt>=policy.attempts {raise error}
    let delay=policy.delay(attempt)
    attempt+=1
    @async.sleep(delay)
   }
  }
 }
}
