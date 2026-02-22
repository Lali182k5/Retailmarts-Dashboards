import http.server
import socketserver
import os
import webbrowser

PORT = 8000
DIRECTORY = "retailmart_analytics/06_dashboard"

class Handler(http.server.SimpleHTTPRequestHandler):
    pass

os.chdir(DIRECTORY)
with socketserver.TCPServer(("", PORT), Handler) as httpd:
    print(f"Serving Dashboard at http://localhost:{PORT}")
    print("Press Ctrl+C to stop the server.")
    webbrowser.open(f"http://localhost:{PORT}")
    httpd.serve_forever()
