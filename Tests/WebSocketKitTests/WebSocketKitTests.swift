import XCTest
import NIO
import NIOHTTP1
import NIOWebSocket
@testable import WebSocketKit

final class WebSocketKitTests: XCTestCase {
    func testWebSocketEcho() throws {
        let promise = elg.next().makePromise(of: String.self)
        WebSocket.connect(to: "ws://echo.websocket.org", on: elg) { ws in
            ws.send("hello")
            ws.onText { ws, string in
                promise.succeed(string)
                ws.close(promise: nil)
            }
        }.cascadeFailure(to: promise)
        try XCTAssertEqual(promise.futureResult.wait(), "hello")
    }
    
    func testWebSocketWithTLSEcho() throws {
        let promise = elg.next().makePromise(of: String.self)
        WebSocket.connect(to: "wss://echo.websocket.org", on: elg) { ws in
            ws.send("hello")
            ws.onText { ws, string in
                promise.succeed(string)
                ws.close(promise: nil)
            }
        }.cascadeFailure(to: promise)
        try XCTAssertEqual(promise.futureResult.wait(), "hello")
    }

    func testBadHost() throws {
        XCTAssertThrowsError(try WebSocket.connect(host: "asdf", on: elg) { _  in }.wait())
    }

    func testImmediateSend() throws {
        let port = Int.random(in: 8000..<9000)

        let promise = self.elg.next().makePromise(of: String.self)

        let server = try ServerBootstrap(group: self.elg).childChannelInitializer { channel in
            let webSocket = NIOWebSocketServerUpgrader(
                shouldUpgrade: { channel, req in
                    return channel.eventLoop.makeSucceededFuture([:])
                },
                upgradePipelineHandler: { channel, req in
                    return WebSocket.server(on: channel) { ws in
                        ws.send("hello")
                        ws.onText { ws, string in
                            promise.succeed(string)
                            ws.close(promise: nil)
                        }
                    }
                }
            )
            return channel.pipeline.configureHTTPServerPipeline(
                withServerUpgrade: (
                    upgraders: [webSocket],
                    completionHandler: { ctx in
                        // complete
                    }
                )
            )
        }.bind(host: "localhost", port: port).wait()

        WebSocket.connect(to: "ws://localhost:\(port)", on: self.elg) { ws in
            ws.onText { ws, string in
                ws.send("goodbye")
                ws.close(promise: nil)
            }
        }.cascadeFailure(to: promise)

        try XCTAssertEqual(promise.futureResult.wait(), "goodbye")
        try server.close(mode: .all).wait()
    }

    func testWebSocketPong() throws {
        let port = Int.random(in: 8000..<9000)

        let pongPromise = self.elg.next().makePromise(of: String.self)

        let server = try ServerBootstrap(group: self.elg).childChannelInitializer { channel in
            let webSocket = NIOWebSocketServerUpgrader(
                shouldUpgrade: { channel, req in
                    return channel.eventLoop.makeSucceededFuture([:])
                },
                upgradePipelineHandler: { channel, req in
                    return WebSocket.server(on: channel) { ws in
                        ws.onPing { ws in
                            ws.close(promise: nil)
                        }
                    }
                }
            )
            return channel.pipeline.configureHTTPServerPipeline(
                withServerUpgrade: (
                    upgraders: [webSocket],
                    completionHandler: { ctx in
                        // complete
                    }
                )
            )
        }.bind(host: "localhost", port: port).wait()

        WebSocket.connect(to: "ws://localhost:\(port)", on: self.elg) { ws in
            ws.send(raw: Data(), opcode: .ping)
            ws.onPong { ws in
                pongPromise.succeed("pong")
                ws.close(promise: nil)
            }
        }.cascadeFailure(to: pongPromise)

        try XCTAssertEqual(pongPromise.futureResult.wait(), "pong")
        try server.close(mode: .all).wait()
    }

    func testErrorCode() throws {
        let port = Int.random(in: 8000..<9000)

        let promise = self.elg.next().makePromise(of: WebSocketErrorCode.self)

        _ = try ServerBootstrap(group: self.elg).childChannelInitializer { channel in
            let webSocket = NIOWebSocketServerUpgrader(
                shouldUpgrade: { channel, req in
                    return channel.eventLoop.makeSucceededFuture([:])
                },
                upgradePipelineHandler: { channel, req in
                    return WebSocket.server(on: channel) { ws in
                        ws.close(code: .normalClosure, promise: nil)
                    }
                }
            )
            return channel.pipeline.configureHTTPServerPipeline(
                withServerUpgrade: (
                    upgraders: [webSocket],
                    completionHandler: { ctx in
                        // complete
                    }
                )
            )
        }.bind(host: "localhost", port: port).wait()

        WebSocket.connect(to: "ws://localhost:\(port)", on: self.elg) { ws in
            ws.onText { ws, string in
                ws.send("goodbye")
            }
            ws.onClose.whenSuccess {
                promise.succeed(ws.closeCode!)
                XCTAssertEqual(ws.closeCode, WebSocketErrorCode.normalClosure)
            }
        }.cascadeFailure(to: promise)

        try XCTAssertEqual(promise.futureResult.wait(), WebSocketErrorCode.normalClosure)
    }

    func testHeadersAreSent() throws {
        let port = Int.random(in: 8000..<9000)

        let promise = self.elg.next().makePromise(of: String.self)

        let server = try ServerBootstrap(group: self.elg).childChannelInitializer { channel in
            let webSocket = NIOWebSocketServerUpgrader(
                shouldUpgrade: { channel, req in
                    return channel.eventLoop.makeSucceededFuture([:])
                },
                upgradePipelineHandler: { channel, req in
                    promise.succeed(req.headers["Auth"].first!)
                    return WebSocket.server(on: channel) { ws in
                        ws.close(promise: nil)
                    }
                }
            )
            return channel.pipeline.configureHTTPServerPipeline(
                withServerUpgrade: (
                    upgraders: [webSocket],
                    completionHandler: { ctx in
                        // complete
                    }
                )
            )
        }.bind(host: "localhost", port: port).wait()

        WebSocket.connect(
            to: "ws://localhost:\(port)",
            headers: ["Auth": "supersecretsauce"],
            on: self.elg) { ws in
                _ = ws.close()
        }.cascadeFailure(to: promise)

        try XCTAssertEqual(promise.futureResult.wait(), "supersecretsauce")
        try server.close(mode: .all).wait()
    }

    var elg: EventLoopGroup!
    override func setUp() {
        // needs to be at least two to avoid client / server on same EL timing issues
        self.elg = MultiThreadedEventLoopGroup(numberOfThreads: 2)
    }
    override func tearDown() {
        try! self.elg.syncShutdownGracefully()
    }
}
