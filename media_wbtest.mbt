///|
fn packet(sequence : Int, timestamp? : UInt = 0U, ssrc? : UInt = 1U, marker? : Bool = true, payload? : Bytes = b"abc") -> @rtp.Packet raise {
 @rtp.Packet::new(payload_type=b'\x60',sequence_number=sequence.to_uint16(),timestamp~,ssrc~,marker~,payload~)
}

///|
test "sequence wrap gap late duplicate and source switch" {
 let s=TrackStats::new()
 for n in [65534,65535,0,2,1,2] {s.observe(packet(n))}
 let v=s.snapshot()
 assert_eq(v.packets,6L)
 assert_eq(v.forward_gaps,1L)
 assert_eq(v.late_or_duplicate,2L)
 s.observe(packet(50,ssrc=2U))
 assert_eq(s.snapshot().source_changes,1L)
 assert_eq(s.snapshot().forward_gaps,1L)
 let clock=Clock::new(90000)
 assert_eq(clock.millis(4294967200U),0L)
 assert_eq(clock.millis(89904U),1000L)
 assert_eq(clock.millis(44904U),500L)
}

///|
test "bounded queue drops oldest and channel map forbids collisions" {
 let q=MediaQueue::new(capacity=2)
 for n in [0,1,2]{q.push(Rtp(0,packet(n)))}
 assert_eq(q.discarded(),1L)
 assert_true(q.pop() is Some(Rtp(0,p)) && p.sequence_number().to_int()==1)
 assert_eq(q.length(),1)
 let channels=ChannelMap::new()
 channels.bind(0,Tcp(2,3))
 expect_error(()=>channels.bind(1,Tcp(2,3)))
 assert_true(channels.route(2,packet(5).marshal()) is Rtp(0,p) && p.sequence_number().to_int()==5)
 expect_error(()=>ignore(channels.route(7,b"")))
 expect_error(()=>ignore(channels.route(2,b"invalid")))
}

///|
test "frame fragmentation loss and budget" {
 let assembler=FrameAssembler::new(@rtp.H264,max_bytes=100)
 // FU-A reconstructs one IDR NAL unit 65 61 62 63 64.
 assert_true(assembler.push(packet(1,marker=false,payload=b"\x7c\x85ab")) is None)
 let frame=assembler.push(packet(2,payload=b"\x7c\x45cd")).unwrap()
 assert_eq(frame.packets,2)
 assert_true(frame.data.length()>=5)
 assembler.reset()
 ignore(assembler.push(packet(1,marker=false,payload=b"\x7c\x85ab")))
 assert_true(assembler.push(packet(3,payload=b"\x7c\x45cd")) is None)
 let small=FrameAssembler::new(@rtp.G711,max_bytes=2)
 expect_error(()=>ignore(small.push(packet(1))))
}

///|
test "SDP selects audio video and resolves aggregate" {
 let text=b"v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\ns=fixture\r\nt=0 0\r\na=control:*\r\nm=video 0 RTP/AVP 96\r\na=rtpmap:96 H264/90000\r\na=control:trackID=0\r\nm=audio 0 RTP/AVP 0\r\na=control:trackID=1\r\n"
 let d=describe(text,"rtsp://host/live/")
 assert_eq(d.tracks.length(),2)
 assert_eq(d.tracks[0].control,"rtsp://host/live/trackID=0")
 assert_eq(d.select([1])[0].kind,"audio")
 expect_error(()=>ignore(d.select([0,0])))
 expect_error(()=>ignore(describe(b"garbage","rtsp://host/a")))
}

///|
test "reconnect policy is bounded" {
 let p=ReconnectPolicy::new(attempts=5,initial_ms=100,maximum_ms=300)
 assert_eq([p.delay(0),p.delay(1),p.delay(2),p.delay(4)],[100,200,300,300])
 expect_error(()=>ignore(p.delay(5)))
}

