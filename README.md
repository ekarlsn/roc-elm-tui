[![Roc-Lang][roc_badge]][roc_link]

[roc_badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Fpastebin.com%2Fraw%2FcFzuCCd7
[roc_link]: https://github.com/roc-lang/roc

# roc-elm-tui

A Roc [platform](https://github.com/roc-lang/roc/wiki/Roc-concepts-explained#platform) for building Elm-inspired terminal user interfaces.

Applications follow the [Elm Architecture](https://guide.elm-lang.org/architecture/): define a `Model`, an `Event` type, and three functions — `init`, `update`, and `view`. The platform drives the event loop, delivering keyboard input, TCP events, and timer ticks as typed `Event` values, and rendering each `view` result to the terminal.

## Supported targets

| Roc target | Operating system | Architecture |
| --- | --- | --- |
| `x64mac` | macOS | x86-64 |
| `arm64mac` | macOS | ARM64 |
| `x64musl` | Linux (musl) | x86-64 |
| `arm64musl` | Linux (musl) | ARM64 |
| `x64win` | Windows | x86-64 |

## Application structure

An application exposes a `Model` type, an `Event` type, and an `application` record:

```roc
app [Model, Event, application] { pf: platform "...", ... }

application = { init, update, view }
```

| Function | Signature |
| --- | --- |
| `init` | `Context, List(Str) -> { m : Model, sub : Subscriptions(Event), effects : List(Effect) }` |
| `update` | `Context, Model, Event -> { m : Model, sub : Subscriptions(Event), effects : List(Effect) }` |
| `view` | `TerminalSettings, Model -> [RawMode(List(List(Terminal))), Nothing]` |

Returning `Subscriptions.none` from `update` exits the application cleanly.

### Subscriptions

| Subscription | Description |
| --- | --- |
| `stdin` | Keyboard input, parsed as `ANSI.Input` |
| `accept_tcp_connection` | TCP server: accept incoming connections on a host/port |
| `tcp_connect` | TCP client: connect to a remote server |
| `tcp_receive` | Receive bytes from a connected TCP stream |
| `timer` | One-shot timer firing at a given nanosecond timestamp |

### Effects

| Effect | Description |
| --- | --- |
| `Print(Str)` | Write a string to stdout |
| `WriteToFile({ filename, content })` | Write a string to a file |
| `TcpSend({ stream, data })` | Send bytes over a TCP stream |
| `Exit(U16)` | Exit the application with an exit code |

## Examples

The [examples](examples/) directory contains runnable apps:

| File | Description |
| --- | --- |
| `elm-example.roc` | Minimal counter — keyboard input updates a cursor-highlighted list |
| `timer-example.roc` | Fires a timer every 5 seconds and displays the count |
| `tcp-echo-server.roc` | TCP server that echoes received bytes back to all connected clients |
| `tcp-client.roc` | TCP client that sends messages on keypress and displays replies |

Build the platform first (see [CONTRIBUTING.md](CONTRIBUTING.md)), then run an example:

```sh
roc run examples/elm-example.roc
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup instructions, build steps, and how to regenerate Rust glue.
