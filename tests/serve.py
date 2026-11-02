# A small server for the tests: serve.py <port> [host]. Not python's http.server, which
# looks up its own hostname between binding and listening; on a machine with slow reverse
# DNS (CI's macOS) that takes over a minute.
import http.server, socket, socketserver, sys

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b"ok\n")
    def log_message(self, *args):
        pass

host = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1"
class Server(socketserver.TCPServer):
    allow_reuse_address = True
    address_family = socket.AF_INET6 if ":" in host else socket.AF_INET

Server((host, int(sys.argv[1])), Handler).serve_forever()
