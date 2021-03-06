import XCTest
import PerfectLib
import PerfectNet
import PerfectThread
import PerfectHTTP
@testable import PerfectHTTPServer

func ShimHTTPRequest() -> HTTP11Request {
	return HTTP11Request(connection: NetTCP())
}

class PerfectHTTPServerTests: XCTestCase {
	
	override func setUp() {
		super.setUp()
		compatRoutes = nil
	}
	
	func testHPACKEncode() {
		
		let encoder = HPACKEncoder(maxCapacity: 256)
		let b = Bytes()
		
		let headers = [
			(":method", "POST"),
			(":scheme", "https"),
			(":path", "/3/device/00fc13adff785122b4ad28809a3420982341241421348097878e577c991de8f0"),
			("host", "api.development.push.apple.com"),
			("apns-id", "eabeae54-14a8-11e5-b60b-1697f925ec7b"),
			("apns-expiration", "0"),
			("apns-priority", "10"),
			("content-length", "33")]
		do {
			for (n, v) in headers {
				try encoder.encodeHeader(out: b, name: UTF8Encoding.decode(string: n), value: UTF8Encoding.decode(string: v), sensitive: false)
			}
			
			class Listener: HeaderListener {
				var headers = [(String, String)]()
				func addHeader(name nam: [UInt8], value: [UInt8], sensitive: Bool) {
					self.headers.append((UTF8Encoding.encode(bytes: nam), UTF8Encoding.encode(bytes: value)))
				}
			}
			
			let decoder = HPACKDecoder(maxHeaderSize: 256, maxHeaderTableSize: 256)
			let l = Listener()
			try decoder.decode(input: b, headerListener: l)
			
			XCTAssert(l.headers.count == headers.count)
			
			for i in 0..<headers.count {
				let h1 = headers[i]
				let h2 = l.headers[i]
				
				XCTAssert(h1.0 == h2.0)
				XCTAssert(h1.1 == h2.1)
			}
			
		}
		catch {
			XCTAssert(false, "Exception \(error)")
		}
	}
	
	func testWebConnectionHeadersWellFormed() {
		let connection = ShimHTTPRequest()
		
		let fullHeaders = "GET / HTTP/1.1\r\nX-Foo: bar\r\nX-Bar: \r\nContent-Type: application/x-www-form-urlencoded\r\n\r\n"
		
		XCTAssert(false == connection.didReadSomeBytes(UTF8Encoding.decode(string: fullHeaders)) {
			ok in
			
			guard case .ok = ok else {
				return XCTAssert(false, "\(ok)")
			}
			XCTAssertTrue(connection.header(.custom(name: "x-foo")) == "bar", "\(connection.headers)")
			XCTAssertTrue(connection.header(.custom(name: "x-bar")) == "", "\(connection.headers)")
			XCTAssertTrue(connection.contentType == "application/x-www-form-urlencoded", "\(connection.headers)")
		})
	}
	
	func testWebConnectionHeadersLF() {
		let connection = ShimHTTPRequest()
		
		let fullHeaders = "GET / HTTP/1.1\nX-Foo: bar\nX-Bar: \nContent-Type: application/x-www-form-urlencoded\n\n"
		
		XCTAssert(false == connection.didReadSomeBytes(UTF8Encoding.decode(string: fullHeaders)) {
			ok in
			
			guard case .ok = ok else {
				return XCTAssert(false, "\(ok)")
			}
			XCTAssertTrue(connection.header(.custom(name: "x-foo")) == "bar", "\(connection.headers)")
			XCTAssertTrue(connection.header(.custom(name: "x-bar")) == "", "\(connection.headers)")
			XCTAssertTrue(connection.contentType == "application/x-www-form-urlencoded", "\(connection.headers)")
		})
	}
	
	func testWebConnectionHeadersMalormed() {
		let connection = ShimHTTPRequest()
		
		let fullHeaders = "GET / HTTP/1.1\r\nX-Foo: bar\rX-Bar: \r\nContent-Type: application/x-www-form-urlencoded\r\n\r\n"
		
		XCTAssert(false == connection.didReadSomeBytes(UTF8Encoding.decode(string: fullHeaders)) {
			ok in
			
			guard case .badRequest = ok else {
				return XCTAssert(false, "\(ok)")
			}
		})
	}
	
	func testWebConnectionHeadersFolded() {
		let connection = ShimHTTPRequest()
		
		let fullHeaders = "GET / HTTP/1.1\r\nX-Foo: bar\r\n bar\r\nX-Bar: foo\r\n  foo\r\nContent-Type: application/x-www-form-urlencoded\r\n\r\n"
		
		XCTAssert(false == connection.didReadSomeBytes(UTF8Encoding.decode(string: fullHeaders)) {
			ok in
			
			guard case .ok = ok else {
				return XCTAssert(false, "\(ok)")
			}
			let wasFoldedValue = connection.header(.custom(name: "x-foo"))
			XCTAssertTrue(wasFoldedValue == "bar bar", "\(connection.headers)")
			XCTAssertTrue(connection.header(.custom(name: "x-bar")) == "foo  foo", "\(connection.headers)")
			XCTAssertTrue(connection.contentType == "application/x-www-form-urlencoded", "\(connection.headers)")
		})
	}
	
	func testWebConnectionHeadersTooLarge() {
		let connection = ShimHTTPRequest()
		
		var fullHeaders = "GET / HTTP/1.1\r\nX-Foo:"
		for _ in 0..<(1024*81) {
			fullHeaders.append(" bar")
		}
		fullHeaders.append("\r\n\r\n")
		
		XCTAssert(false == connection.didReadSomeBytes(UTF8Encoding.decode(string: fullHeaders)) {
			ok in
			
			guard case .requestEntityTooLarge = ok else {
				return XCTAssert(false, "\(ok)")
			}
			XCTAssert(true)
		})
	}
	
	func testWebRequestQueryParam() {
		let req = ShimHTTPRequest()
		req.queryString = "yabba=dabba&y=asd==&doo=fi+☃&fi=&fo=fum"
		XCTAssert(req.param(name: "doo") == "fi ☃")
		XCTAssert(req.param(name: "fi") == "")
		XCTAssert(req.param(name: "y") == "asd==")
	}
	
	func testWebRequestPostParam() {
		let req = ShimHTTPRequest()
		req.postBodyBytes = Array("yabba=dabba&y=asd==&doo=fi+☃&fi=&fo=fum".utf8)
		XCTAssert(req.param(name: "doo") == "fi ☃")
		XCTAssert(req.param(name: "fi") == "")
		XCTAssert(req.param(name: "y") == "asd==")
	}
	
	func testWebRequestCookie() {
		let req = ShimHTTPRequest()
		req.setHeader(.cookie, value: "yabba=dabba; doo=fi☃; fi=; fo=fum")
		for cookie in req.cookies {
			if cookie.0 == "doo" {
				XCTAssert(cookie.1 == "fi☃")
			}
			if cookie.0 == "fi" {
				XCTAssert(cookie.1 == "")
			}
		}
	}
	
	func testSimpleHandler() {
		let port = 8282 as UInt16
		let msg = "Hello, world!"
		var routes = Routes()
		routes.add(method: .get, uri: "/", handler: {
				request, response in
				response.addHeader(.contentType, value: "text/plain")
				response.appendBody(string: msg)
				response.completed()
			}
		)
		let serverExpectation = self.expectation(description: "server")
		let clientExpectation = self.expectation(description: "client")
		
		let server = HTTPServer()
		server.addRoutes(routes)
		server.serverPort = port
		func endClient() {
			server.stop()
			clientExpectation.fulfill()
		}
		
		Threading.dispatch {
			do {
				try server.start()
			} catch PerfectError.networkError(let err, let msg) {
				XCTAssert(false, "Network error thrown: \(err) \(msg)")
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
			}
			serverExpectation.fulfill()
		}
		Threading.sleep(seconds: 1.0)
		Threading.dispatch {
			do {
				try NetTCP().connect(address: "127.0.0.1", port: port, timeoutSeconds: 5.0) {
					net in
					
					guard let net = net else {
						XCTAssert(false, "Could not connect to server")
						return endClient()
					}
					let reqStr = "GET / HTTP/1.0\r\nHost: localhost:\(port)\r\nFrom: me@host.com\r\n\r\n"
					net.write(string: reqStr) {
						count in
						
						guard count == reqStr.utf8.count else {
							XCTAssert(false, "Could not write request \(count) != \(reqStr.utf8.count)")
							return endClient()
						}
						
						Threading.sleep(seconds: 2.0)
						net.readSomeBytes(count: 1024) {
							bytes in
							
							guard let bytes = bytes, bytes.count > 0 else {
								XCTAssert(false, "Could not read bytes from server")
								return endClient()
							}
							
							let str = UTF8Encoding.encode(bytes: bytes)
							let splitted = str.characters.split(separator: "\r\n").map(String.init)
							
							XCTAssert(splitted.last == msg)
							
							endClient()
						}
					}
				}
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
				endClient()
			}
		}
		
		self.waitForExpectations(timeout: 10000, handler: {
			_ in
			
		})
	}
	
	func testSimpleStreamingHandler() {
		let port = 8282 as UInt16
		var routes = Routes()
		routes.add(method: .get, uri: "/", handler: {
				request, response in
				response.addHeader(.contentType, value: "text/plain")
				response.isStreaming = true
				response.appendBody(string: "A")
				response.push {
					ok in
					XCTAssert(ok, "Failed in .push")
					response.appendBody(string: "BC")
					response.completed()
				}
			}
		)
		let serverExpectation = self.expectation(description: "server")
		let clientExpectation = self.expectation(description: "client")
		
		let server = HTTPServer()
		server.serverPort = port
		server.addRoutes(routes)
		
		func endClient() {
			server.stop()
			clientExpectation.fulfill()
		}
		
		Threading.dispatch {
			do {
				try server.start()
			} catch PerfectError.networkError(let err, let msg) {
				XCTAssert(false, "Network error thrown: \(err) \(msg)")
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
			}
			serverExpectation.fulfill()
		}
		Threading.sleep(seconds: 1.0)
		Threading.dispatch {
			do {
				try NetTCP().connect(address: "127.0.0.1", port: port, timeoutSeconds: 5.0) {
					net in
					
					guard let net = net else {
						XCTAssert(false, "Could not connect to server")
						return endClient()
					}
					let reqStr = "GET / HTTP/1.0\r\nHost: localhost:\(port)\r\nFrom: me@host.com\r\n\r\n"
					net.write(string: reqStr) {
						count in
						
						guard count == reqStr.utf8.count else {
							XCTAssert(false, "Could not write request \(count) != \(reqStr.utf8.count)")
							return endClient()
						}
						
						Threading.sleep(seconds: 2.0)
						net.readSomeBytes(count: 2048) {
							bytes in
							
							guard let bytes = bytes, bytes.count > 0 else {
								XCTAssert(false, "Could not read bytes from server")
								return endClient()
							}
							
							let str = UTF8Encoding.encode(bytes: bytes)
							let splitted = str.characters.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
							let compare = ["HTTP/1.0 200 OK",
							               "Content-Type: text/plain",
							               "Transfer-Encoding: chunked",
							               "",
							               "1",
							               "A",
							               "2",
							               "BC",
							               "0",
							               "",
							               ""]
							XCTAssert(splitted.count == compare.count)
							for (a, b) in zip(splitted, compare) {
								XCTAssert(a == b, "\(splitted) != \(compare)")
							}
							
							endClient()
						}
					}
				}
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
				endClient()
			}
		}
		
		self.waitForExpectations(timeout: 10000, handler: {
			_ in
			
		})
	}
	
	func testSlowClient() {
		let port = 8282 as UInt16
		let msg = "Hello, world!"
		var routes = Routes()
		routes.add(method: .get, uri: "/", handler: {
				request, response in
				response.addHeader(.contentType, value: "text/plain")
				response.appendBody(string: msg)
				response.completed()
			}
		)
		let serverExpectation = self.expectation(description: "server")
		let clientExpectation = self.expectation(description: "client")
		
		let server = HTTPServer()
		server.serverPort = port
		server.addRoutes(routes)
		
		func endClient() {
			server.stop()
			clientExpectation.fulfill()
		}
		
		Threading.dispatch {
			do {
				try server.start()
			} catch PerfectError.networkError(let err, let msg) {
				XCTAssert(false, "Network error thrown: \(err) \(msg)")
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
			}
			serverExpectation.fulfill()
		}
		Threading.sleep(seconds: 1.0)
		Threading.dispatch {
			do {
				try NetTCP().connect(address: "127.0.0.1", port: port, timeoutSeconds: 5.0) {
					net in
					
					guard let net = net else {
						XCTAssert(false, "Could not connect to server")
						return endClient()
					}
					var reqIt = Array("GET / HTTP/1.0\r\nHost: localhost:\(port)\r\nFrom: me@host.com\r\n\r\n".utf8).makeIterator()
					func pushChar() {
						if let b = reqIt.next() {
							let a = [b]
							net.write(bytes: a) {
								wrote in
								guard 1 == wrote else {
									XCTAssert(false, "Could not write request \(wrote) != \(1)")
									return endClient()
								}
								Threading.sleep(seconds: 0.5)
								Threading.dispatch {
									pushChar()
								}
							}
						} else {
							Threading.sleep(seconds: 2.0)
							net.readSomeBytes(count: 1024) {
								bytes in
								guard let bytes = bytes, bytes.count > 0 else {
									XCTAssert(false, "Could not read bytes from server")
									return endClient()
								}
								let str = UTF8Encoding.encode(bytes: bytes)
								let splitted = str.characters.split(separator: "\r\n").map(String.init)
								XCTAssert(splitted.last == msg)
								endClient()
							}
						}
					}
					pushChar()
				}
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
				endClient()
			}
		}
		
		self.waitForExpectations(timeout: 20000, handler: {
			_ in
			
		})
	}
	
	static var oneSet = false, twoSet = false, threeSet = false
	
	func testRequestFilters() {
		let port = 8282 as UInt16
		let msg = "Hello, world!"
		
		PerfectHTTPServerTests.oneSet = false
		PerfectHTTPServerTests.twoSet = false
		PerfectHTTPServerTests.threeSet = false
		
		struct Filter1: HTTPRequestFilter {
			func filter(request: HTTPRequest, response: HTTPResponse, callback: (HTTPRequestFilterResult) -> ()) {
				PerfectHTTPServerTests.oneSet = true
				callback(.continue(request, response))
			}
		}
		struct Filter2: HTTPRequestFilter {
			func filter(request: HTTPRequest, response: HTTPResponse, callback: (HTTPRequestFilterResult) -> ()) {
				XCTAssert(PerfectHTTPServerTests.oneSet)
				XCTAssert(!PerfectHTTPServerTests.twoSet && !PerfectHTTPServerTests.threeSet)
				PerfectHTTPServerTests.twoSet = true
				callback(.execute(request, response))
			}
		}
		struct Filter3: HTTPRequestFilter {
			func filter(request: HTTPRequest, response: HTTPResponse, callback: (HTTPRequestFilterResult) -> ()) {
				XCTAssert(false, "This filter should be skipped")
				callback(.continue(request, response))
			}
		}
		struct Filter4: HTTPRequestFilter {
			func filter(request: HTTPRequest, response: HTTPResponse, callback: (HTTPRequestFilterResult) -> ()) {
				XCTAssert(PerfectHTTPServerTests.oneSet && PerfectHTTPServerTests.twoSet)
				XCTAssert(!PerfectHTTPServerTests.threeSet)
				PerfectHTTPServerTests.threeSet = true
				callback(.halt(request, response))
			}
		}
		
		let requestFilters: [(HTTPRequestFilter, HTTPFilterPriority)] = [(Filter1(), HTTPFilterPriority.high), (Filter2(), HTTPFilterPriority.medium), (Filter3(), HTTPFilterPriority.medium), (Filter4(), HTTPFilterPriority.low)]
		var routes = Routes()
		routes.add(method: .get, uri: "/", handler: {
				request, response in
				XCTAssert(false, "This handler should not execute")
				response.addHeader(.contentType, value: "text/plain")
				response.appendBody(string: msg)
				response.completed()
			}
		)
		let serverExpectation = self.expectation(description: "server")
		let clientExpectation = self.expectation(description: "client")
		
		let server = HTTPServer()
		server.setRequestFilters(requestFilters)
		server.serverPort = port
		server.addRoutes(routes)
		func endClient() {
			server.stop()
			clientExpectation.fulfill()
		}
		
		Threading.dispatch {
			do {
				try server.start()
			} catch PerfectError.networkError(let err, let msg) {
				XCTAssert(false, "Network error thrown: \(err) \(msg)")
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
			}
			serverExpectation.fulfill()
		}
		Threading.sleep(seconds: 1.0)
		Threading.dispatch {
			do {
				try NetTCP().connect(address: "127.0.0.1", port: port, timeoutSeconds: 5.0) {
					net in
					
					guard let net = net else {
						XCTAssert(false, "Could not connect to server")
						return endClient()
					}
					let reqStr = "GET / HTTP/1.0\r\nHost: localhost:\(port)\r\nFrom: me@host.com\r\n\r\n"
					net.write(string: reqStr) {
						count in
						
						guard count == reqStr.utf8.count else {
							XCTAssert(false, "Could not write request \(count) != \(reqStr.utf8.count)")
							return endClient()
						}
						
						Threading.sleep(seconds: 3.0)
						net.readSomeBytes(count: 1024) {
							bytes in
							
							guard let bytes = bytes, bytes.count > 0 else {
								XCTAssert(false, "Could not read bytes from server")
								return endClient()
							}
							
							endClient()
						}
					}
				}
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
				endClient()
			}
		}
		
		self.waitForExpectations(timeout: 10000, handler: {
			_ in
			XCTAssert(PerfectHTTPServerTests.oneSet && PerfectHTTPServerTests.twoSet && PerfectHTTPServerTests.threeSet)
		})
	}
	
	func testResponseFilters() {
		let port = 8282 as UInt16
		
		struct Filter1: HTTPResponseFilter {
			func filterHeaders(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				response.setHeader(.custom(name: "X-Custom"), value: "Value")
				callback(.continue)
			}
			func filterBody(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				callback(.continue)
			}
		}
		
		struct Filter2: HTTPResponseFilter {
			func filterHeaders(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				callback(.continue)
			}
			func filterBody(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				var b = response.bodyBytes
				b = b.map { $0 == 65 ? 97 : $0 }
				response.bodyBytes = b
				callback(.continue)
			}
		}
		
		struct Filter3: HTTPResponseFilter {
			func filterHeaders(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				callback(.continue)
			}
			func filterBody(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				var b = response.bodyBytes
				b = b.map { $0 == 66 ? 98 : $0 }
				response.bodyBytes = b
				callback(.done)
			}
		}
		
		struct Filter4: HTTPResponseFilter {
			func filterHeaders(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				callback(.continue)
			}
			func filterBody(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				XCTAssert(false, "This should not execute")
				callback(.done)
			}
		}
		
		let responseFilters: [(HTTPResponseFilter, HTTPFilterPriority)] = [
			(Filter1(), HTTPFilterPriority.high),
			(Filter2(), HTTPFilterPriority.medium),
			(Filter3(), HTTPFilterPriority.low),
			(Filter4(), HTTPFilterPriority.low)
		]
		
		var routes = Routes()
		routes.add(method: .get, uri: "/", handler: {
				request, response in
				response.addHeader(.contentType, value: "text/plain")
				response.appendBody(string: "ABZABZ")
				response.completed()
			}
		)
		let serverExpectation = self.expectation(description: "server")
		let clientExpectation = self.expectation(description: "client")
		
		let server = HTTPServer()
		server.setResponseFilters(responseFilters)
		server.serverPort = port
		server.addRoutes(routes)
		
		func endClient() {
			server.stop()
			clientExpectation.fulfill()
		}
		
		Threading.dispatch {
			do {
				try server.start()
			} catch PerfectError.networkError(let err, let msg) {
				XCTAssert(false, "Network error thrown: \(err) \(msg)")
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
			}
			serverExpectation.fulfill()
		}
		Threading.sleep(seconds: 1.0)
		Threading.dispatch {
			do {
				try NetTCP().connect(address: "127.0.0.1", port: port, timeoutSeconds: 5.0) {
					net in
					
					guard let net = net else {
						XCTAssert(false, "Could not connect to server")
						return endClient()
					}
					let reqStr = "GET / HTTP/1.0\r\nHost: localhost:\(port)\r\nFrom: me@host.com\r\n\r\n"
					net.write(string: reqStr) {
						count in
						
						guard count == reqStr.utf8.count else {
							XCTAssert(false, "Could not write request \(count) != \(reqStr.utf8.count)")
							return endClient()
						}
						
						Threading.sleep(seconds: 3.0)
						net.readSomeBytes(count: 2048) {
							bytes in
							
							guard let bytes = bytes, bytes.count > 0 else {
								XCTAssert(false, "Could not read bytes from server")
								return endClient()
							}
							
							let str = UTF8Encoding.encode(bytes: bytes)
							let splitted = str.characters.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
							let compare = ["HTTP/1.0 200 OK",
							               "Content-Type: text/plain",
							               "Content-Length: 6",
							               "X-Custom: Value",
							               "",
							               "abZabZ"]
							XCTAssert(splitted.count == compare.count)
							for (a, b) in zip(splitted, compare) {
								XCTAssert(a == b, "\(splitted) != \(compare)")
							}
							
							endClient()
						}
					}
				}
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
				endClient()
			}
		}
		
		self.waitForExpectations(timeout: 10000, handler: {
			_ in
		})
	}
	
	func testStreamingResponseFilters() {
		let port = 8282 as UInt16
		
		struct Filter1: HTTPResponseFilter {
			func filterHeaders(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				response.setHeader(.custom(name: "X-Custom"), value: "Value")
				callback(.continue)
			}
			func filterBody(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				callback(.continue)
			}
		}
		
		struct Filter2: HTTPResponseFilter {
			func filterHeaders(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				callback(.continue)
			}
			func filterBody(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				var b = response.bodyBytes
				b = b.map { $0 == 65 ? 97 : $0 }
				response.bodyBytes = b
				callback(.continue)
			}
		}
		
		struct Filter3: HTTPResponseFilter {
			func filterHeaders(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				callback(.continue)
			}
			func filterBody(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				var b = response.bodyBytes
				b = b.map { $0 == 66 ? 98 : $0 }
				response.bodyBytes = b
				callback(.done)
			}
		}
		
		struct Filter4: HTTPResponseFilter {
			func filterHeaders(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				callback(.continue)
			}
			func filterBody(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
				XCTAssert(false, "This should not execute")
				callback(.done)
			}
		}
		
		let responseFilters: [(HTTPResponseFilter, HTTPFilterPriority)] = [
			(Filter1(), HTTPFilterPriority.high),
			(Filter2(), HTTPFilterPriority.medium),
			(Filter3(), HTTPFilterPriority.low),
			(Filter4(), HTTPFilterPriority.low)
		]
		
		var routes = Routes()
		routes.add(method: .get, uri: "/", handler: {
				request, response in
				response.addHeader(.contentType, value: "text/plain")
				response.isStreaming = true
				response.appendBody(string: "ABZ")
				response.push {
					_ in
					response.appendBody(string: "ABZ")
					response.completed()
				}
			}
		)
		let serverExpectation = self.expectation(description: "server")
		let clientExpectation = self.expectation(description: "client")
		
		let server = HTTPServer()
		server.setResponseFilters(responseFilters)
		server.serverPort = port
		server.addRoutes(routes)
		
		func endClient() {
			server.stop()
			clientExpectation.fulfill()
		}
		
		Threading.dispatch {
			do {
				try server.start()
			} catch PerfectError.networkError(let err, let msg) {
				XCTAssert(false, "Network error thrown: \(err) \(msg)")
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
			}
			serverExpectation.fulfill()
		}
		Threading.sleep(seconds: 1.0)
		Threading.dispatch {
			do {
				try NetTCP().connect(address: "127.0.0.1", port: port, timeoutSeconds: 5.0) {
					net in
					
					guard let net = net else {
						XCTAssert(false, "Could not connect to server")
						return endClient()
					}
					let reqStr = "GET / HTTP/1.0\r\nHost: localhost:\(port)\r\nFrom: me@host.com\r\n\r\n"
					net.write(string: reqStr) {
						count in
						
						guard count == reqStr.utf8.count else {
							XCTAssert(false, "Could not write request \(count) != \(reqStr.utf8.count)")
							return endClient()
						}
						
						Threading.sleep(seconds: 3.0)
						net.readSomeBytes(count: 2048) {
							bytes in
							
							guard let bytes = bytes, bytes.count > 0 else {
								XCTAssert(false, "Could not read bytes from server")
								return endClient()
							}
							
							let str = UTF8Encoding.encode(bytes: bytes)
							let splitted = str.characters.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
							let compare = ["HTTP/1.0 200 OK",
							               "Content-Type: text/plain",
							               "Transfer-Encoding: chunked",
							               "X-Custom: Value",
							               "",
							               "3",
							               "abZ",
							               "3",
							               "abZ",
							               "0",
							               "",
							               ""]
							XCTAssert(splitted.count == compare.count)
							for (a, b) in zip(splitted, compare) {
								XCTAssert(a == b, "\(splitted) != \(compare)")
							}
							
							endClient()
						}
					}
				}
			} catch {
				XCTAssert(false, "Error thrown: \(error)")
				endClient()
			}
		}
		
		self.waitForExpectations(timeout: 10000, handler: {
			_ in
		})
	}
	
//	func testServerConf1() {
//		let confData = [
//			"servers": [
//				[
//					"name":"localhost",
//					"port":8080,
//					"routes":[
//						["method":"get", "uri":"/**", "handler":PerfectHTTPServer.HTTPHandler.staticFiles,
//						 "documentRoot":"./webroot"]
//					],
//					"filters":[
//						["type":"request",
//						 "priority":"high",
//						 "name":PerfectHTTPServer.HTTPFilter.customReqFilter],
//						["type":"response",
//						 "priority":"high",
//						 "name":PerfectHTTPServer.HTTPFilter.custom404,
//						 "path":"./webroot/404.html"]
//					],
//					"tlsConfig":["certPath":"/Users/kjessup/new.cert.pem"]
//				],
//				[
//					"name":"localhost redirect",
//					"port":8181,
//					"routes":[
//						["method":"get", "uri":"/**", "handler":PerfectHTTPServer.HTTPHandler.redirect,
//						 "base":"https://localhost:8080"]
//					]
//				]
//			]
//		]
//		
//		do {
//			try HTTPServer.launch(configurationData: confData)
//		} catch {
//			return XCTAssert(false, "Error: \(error)")
//		}
//		XCTAssert(true)
//	}

    static var allTests : [(String, (PerfectHTTPServerTests) -> () throws -> Void)] {
        return [
			("testHPACKEncode", testHPACKEncode),
			("testWebConnectionHeadersWellFormed", testWebConnectionHeadersWellFormed),
			("testWebConnectionHeadersLF", testWebConnectionHeadersLF),
			("testWebConnectionHeadersMalormed", testWebConnectionHeadersMalormed),
			("testWebConnectionHeadersFolded", testWebConnectionHeadersFolded),
			("testWebConnectionHeadersTooLarge", testWebConnectionHeadersTooLarge),
			("testWebRequestQueryParam", testWebRequestQueryParam),
			("testWebRequestCookie", testWebRequestCookie),
			("testWebRequestPostParam", testWebRequestPostParam),
			("testSimpleHandler", testSimpleHandler),
			("testSimpleStreamingHandler", testSimpleStreamingHandler),
			("testRequestFilters", testRequestFilters),
			("testResponseFilters", testResponseFilters),
			("testStreamingResponseFilters", testStreamingResponseFilters),
			("testSlowClient", testSlowClient)
        ]
    }
}
