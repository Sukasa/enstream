# enstream
A simple encryption wrapper for Minitel streams in OpenComputers

This is a really simple library, all it's meant to do is provide for basic encrypted packets in OpenComputers.  Packets are sent and received individually, without being fragmented at the application layer.

Usage of this library is straightfoward:

```local enstream = require("enstream")
local stream = -- Elided, get a Minitel stream

local enc = enstream:New(stream)

-- On one side, but not both:
enc:connect()

enc:write("data!")
```

Data can be received in one of two ways:
1. On fully recieving a packet, an enc_msg event is pushed
2. If a callback is registered with `enc.callback = myFunction`, it is called every time an application-level packet is received
