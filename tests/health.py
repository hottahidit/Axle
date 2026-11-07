# A web server for the tests whose /healthz answers with the status in a file (e.g. 503).
import http.server, socketserver, sys

port, status_file = int(sys.argv[1]), sys.argv[2]

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        code = 200
        if self.path == "/healthz":
            with open(status_file) as f:
                code = int(f.read().strip() or 200)
        self.send_response(code); self.end_headers(); self.wfile.write(b"ok\n")
    def log_message(self, *args):
        pass

class Server(socketserver.TCPServer):
    allow_reuse_address = True

Server(("127.0.0.1", port), Handler).serve_forever()
