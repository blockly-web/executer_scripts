#!/usr/bin/env python3


import cgi
import subprocess
import sys
import urllib.parse
import tempfile  # Add this missing import
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn  # Add this import
from mimetypes import guess_type
from pathlib import Path

PORT = 8080
TEMP_DIR = Path.cwd() / "temp"
TEMP_DIR.mkdir(parents=True, exist_ok=True)
print(f"Using temporary directory: {TEMP_DIR}", file=sys.stderr)

# Define ThreadingHTTPServer for Python 3.6 compatibility
class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True

# --------------------------------------------------------------------------- #
#                              Helper utilities                               #
# --------------------------------------------------------------------------- #
def content_type_for(path: Path) -> str:
    return guess_type(str(path))[0] or "text/plain"


def write_cors_headers(handler: BaseHTTPRequestHandler) -> None:
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.send_header(
        "Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS"
    )
    handler.send_header("Access-Control-Allow-Headers", "Content-Type")


# --------------------------------------------------------------------------- #
#                           Request-handling class                            #
# --------------------------------------------------------------------------- #
class TempHTTPRequestHandler(BaseHTTPRequestHandler):
    server_version = "TempServer/0.1"

    # -----------------------------  GET /output/*  -------------------------- #
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path.startswith("/output/"):
            self.serve_file(parsed.path[len("/output/") :])
        else:
            self.respond_plain(
                HTTPStatus.BAD_REQUEST,
                f"Invalid request: method GET, path {parsed.path}",
            )

    # -----------------------------  POST /upload  --------------------------- #
    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)

        if parsed.path == "/upload" or parsed.path.startswith("/upload"):
            self.handle_upload(parsed)
        else:
            self.respond_plain(
                HTTPStatus.BAD_REQUEST,
                f"Invalid request: method POST, path {parsed.path}",
            )

    # ---------------------------  PUT /command?...  ------------------------- #
    def do_PUT(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/command":
            self.handle_command(parsed)
        else:
            self.respond_plain(
                HTTPStatus.BAD_REQUEST,
                f"Invalid request: method PUT, path {parsed.path}",
            )

    # ----------------------------  OPTIONS (CORS)  -------------------------- #
    def do_OPTIONS(self):
        self.send_response(HTTPStatus.NO_CONTENT)
        write_cors_headers(self)
        self.end_headers()

    # --------------------------------------------------------------------- #
    #                              Handlers                                 #
    # --------------------------------------------------------------------- #
    def serve_file(self, rel_path: str) -> None:
        file_path = (TEMP_DIR / urllib.parse.unquote(rel_path)).resolve()
        try:
            if not file_path.is_file() or not str(file_path).startswith(str(TEMP_DIR)):
                raise FileNotFoundError
            with file_path.open("rb") as fp:
                data = fp.read()
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", content_type_for(file_path))
            self.send_header("Content-Length", str(len(data)))
            write_cors_headers(self)
            self.end_headers()
            self.wfile.write(data)
            print(f"DEBUG: Served {file_path}", file=sys.stderr)
        except FileNotFoundError:
            self.respond_plain(
                HTTPStatus.NOT_FOUND, f"File not found: {file_path}", log=True
            )

    def handle_upload(self, parsed) -> None:
        # query params
        qs = urllib.parse.parse_qs(parsed.query or "")
        custom_filename = qs.get("filename", [None])[0]
        custom_path = qs.get("path", [None])[0]


        ctype, pdict = cgi.parse_header(self.headers.get("Content-Type", ""))
        content_length = int(self.headers.get("Content-Length", 0))
        print(
            f"DEBUG: Upload {custom_filename} {custom_path} {ctype} "
            f"len={content_length}",
            file=sys.stderr,
        )

        if content_length == 0:
            self.respond_plain(HTTPStatus.BAD_REQUEST, "No file content to upload")
            return

        # Prepare target directory and file name
        target_dir = TEMP_DIR / (custom_path or "")

        print(f"DEBUG: Upload target dir: {target_dir}", file=sys.stderr)

        target_dir.mkdir(parents=True, exist_ok=True)
        if custom_filename:
            target_file = target_dir / custom_filename
        else:
            target_file = Path(
                tempfile.mkstemp(prefix="upload_", suffix=".tf", dir=target_dir)[1]
            )

        # Parse body
        if ctype == "multipart/form-data":
            pdict["CONTENT-LENGTH"] = content_length
            form = cgi.FieldStorage(
                fp=self.rfile, headers=self.headers, environ={"REQUEST_METHOD": "POST", **pdict}
            )

            print(f"DEBUG: form: {form}", file=sys.stderr)

            # Complete rewrite of file detection logic
            file_items = []
            
            # First try by directly iterating through form items
            for item in form.list:
                if item.filename:
                    file_items.append(item)
                    print(f"DEBUG: Found file item with filename: {item.filename}", file=sys.stderr)
            
            # If that fails, try a fallback approach
            if not file_items and len(form.list) > 0:
                # Just use the first item in the form regardless
                first_item = form.list[0]
                print(f"DEBUG: Using fallback: first item {first_item}", file=sys.stderr)
                file_items.append(first_item)
            
            print(f"DEBUG: file_items: {file_items}", file=sys.stderr)
                
            if not file_items:
                self.respond_plain(
                    HTTPStatus.BAD_REQUEST, "No file part in multipart upload"
                )
                return
            
            # Fix: Handle file data properly whether it's bytes or string
            with target_file.open("wb") as out_fp:
                file_data = file_items[0].file.read()
                # Convert to bytes if it's a string
                if isinstance(file_data, str):
                    file_data = file_data.encode('utf-8')
                out_fp.write(file_data)
        else:
            # Raw body
            body = self.rfile.read(content_length)
            with target_file.open("wb") as out_fp:
                out_fp.write(body)

        self.respond_plain(
            HTTPStatus.OK, f"File uploaded successfully to {target_file}", log=True
        )

    def handle_command(self, parsed) -> None:
        content_length = int(self.headers.get("Content-Length", 0))
        if content_length == 0:
            self.respond_plain(
                HTTPStatus.BAD_REQUEST, "No command provided in the request body"
            )
            return

        body = self.rfile.read(content_length).decode()
        query = urllib.parse.parse_qs(parsed.query or "")
        project_type = query.get("project-type", [""])[0]
        project_name = query.get("project-name", [""])[0]
        work_dir = TEMP_DIR / project_type / project_name
        work_dir.mkdir(parents=True, exist_ok=True)

        print(
            f"DEBUG: Executing '{body}' in {work_dir} ",
            file=sys.stderr,
        )

        # Execute command
        try:
            completed = subprocess.run(
                body,
                cwd=work_dir,
                shell=True,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                universal_newlines=True,
                timeout=300,
                
            )
            output = completed.stdout + completed.stderr
            (work_dir / "index.html").write_text(output, encoding="utf-8")

            if completed.returncode != 0 or "Error:" in output:
                self.respond_plain(
                    HTTPStatus.INTERNAL_SERVER_ERROR,
                    f"Command failed. Output:\n{output}",
                    log=True,
                )
            else:
                self.respond_plain(
                    HTTPStatus.OK,
                    f"Command executed. Output:\n{output}",
                    log=True,
                )
        except Exception as exc:  # noqa: BLE001
            self.respond_plain(
                HTTPStatus.INTERNAL_SERVER_ERROR,
                f"Execution exception: {exc}",
                log=True,
            )

    # --------------------------------------------------------------------- #
    #                           Utility responses                            #
    # --------------------------------------------------------------------- #
    def respond_plain(
        self,
        status: HTTPStatus,
        message: str,
        *,
        log: bool = False,
        content_type: str = "text/plain; charset=utf-8",
    ):
        data = message.encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        write_cors_headers(self)
        self.end_headers()
        self.wfile.write(data)
        if log:
            print(f"DEBUG: {status} → {message}", file=sys.stderr)

    # --------------------------------------------------------------------- #
    #                        Suppress default logging                       #
    # --------------------------------------------------------------------- #
    def log_message(self, fmt, *args):  # noqa: D401,N802
        # Silence the default access log, keep debug prints in stderr.
        return


# --------------------------------------------------------------------------- #
#                                   Main                                      #
# --------------------------------------------------------------------------- #
def main() -> None:
    with ThreadingHTTPServer(("", PORT), TempHTTPRequestHandler) as httpd:
        print(f"DEBUG: Starting Python server on port {PORT}", file=sys.stderr)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("Server interrupted; shutting down.", file=sys.stderr)


if __name__ == "__main__":
    main()
