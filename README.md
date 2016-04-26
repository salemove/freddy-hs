# RabbitMQ Messaging API supporting request-response

[![Build Status](https://travis-ci.org/salemove/freddy-hs.svg?branch=master)](https://travis-ci.org/salemove/freddy-hs)
[![Code Climate](https://codeclimate.com/github/salemove/freddy-hs/badges/gpa.svg)](https://codeclimate.com/github/salemove/freddy-hs)

## Setup

* Create a connection:

```haskell
import qualified Network.Freddy as Freddy
import qualified Network.Freddy.Request as R

connection <- Freddy.connect "127.0.0.1" "/" "guest" "guest"
```

## Delivering messages

### Simple delivery

#### Send and forget
Sends a `message` to the given `destination`. If there is no consumer then the
message stays in the queue until somebody consumes it.
```haskell
  Freddy.deliver connection R.newReq {
    R.queueName = "notifications.user_signed_in",
    R.body = "{\"user_id\": 1}"
  }
```

#### Expiring messages
Sends a `message` to the given `destination`. If nobody consumes the message in
`timeoutInMs` milliseconds then the message is discarded. This is useful for
showing notifications that must happen in a certain timeframe but guaranteed
delivery is not a strict requirement.
```haskell
  Freddy.deliver connection R.newReq {
    R.queueName = "notifications.user_signed_in",
    R.body = "{\"user_id\": 1}",
    R.timeoutIsMs = 5000
  }
```

### Request delivery
Sends a `message` to the given `destination`. Has a default timeout of 3
seconds and discards the message from the queue if a response hasn't been
returned in that time.
```haskell
  response <- Freddy.deliverWithResponse connection R.newReq {
    R.queueName = "echo",
    R.body = "{\"msg\": \"what did you say?\"}"
  }

  case response of
    Right payload -> putStrLn "Received positive result"
    Left (Freddy.InvalidRequest payload) -> putStrLn "Received error"
    Left Freddy.TimeoutError -> putStrLn "Request timed out"
```

## Responding to messages
```haskell
  processMessage (Freddy.Delivery body replyWith failWith) = replyWith body

  connection <- Freddy.connect "127.0.0.1" "/" "guest" "guest"
  Freddy.respondTo connection "echo" processMessage
```

## Tapping into messages
Listens for messages on a given destination or destinations without
consuming them.

```haskell
  processMessage body = putStrLn body

  connection <- Freddy.connect "127.0.0.1" "/" "guest" "guest"
  Freddy.tapInto connection "notifications.*" processMessage
```

* Note that it is not possible to respond to the message while tapping.
* When tapping the following wildcards are supported in the `queueName`:
  * `#` matching 0 or more words
  * `*` matching exactly one word

Examples:

```haskell
Freddy.tapInto connection "i.#.free" processMessage
```

receives messages that are delivered to `"i.want.to.break.free"`

```haskell
Freddy.tapInto connection "somebody.*.love" processMessage
```

receives messages that are delivered to `somebody.to.love` but doesn't receive messages delivered to `someboy.not.to.love`
