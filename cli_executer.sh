#!/bin/bash
set -euo pipefail

# Configuration: use a "temp" directory in the current working directory.
PORT=8080
TEMP_DIR="$(pwd)/temp"
mkdir -p "$TEMP_DIR"
export TEMP_DIR
echo "Using temporary directory: $TEMP_DIR" >&2


# Connection handler: reads the request, headers, and body, then handles file uploads or command execution.
handle_request() {
  echo "DEBUG: Connection accepted." >&2

  # Read the request line.
  if ! IFS= read -r request_line; then
    echo "DEBUG: Failed to read request line." >&2
    exit 1
  fi
  echo "DEBUG: Request line: '$request_line'" >&2

  # Parse the request line into method, path, and HTTP version.
  method=$(echo "$request_line" | awk '{print $1}')
  path=$(echo "$request_line" | awk '{print $2}')
  http_version=$(echo "$request_line" | awk '{print $3}')
  echo "DEBUG: Method: $method, Path: $path, HTTP Version: $http_version" >&2

  # Process headers.
  content_length=0
  echo "DEBUG: Starting header processing." >&2
  while IFS= read -r header_line; do
    header_line="${header_line%%$'\r'}"
    if [ -z "$header_line" ]; then
      echo "DEBUG: End of headers detected." >&2
      break
    fi
    echo "DEBUG: Header: '$header_line'" >&2
    if [[ "$header_line" =~ ^Content-Length:\ ([0-9]+) ]]; then
      content_length=${BASH_REMATCH[1]}
      echo "DEBUG: Found Content-Length: $content_length" >&2
    fi
  done
  echo "DEBUG: Finished header processing. Content-Length = $content_length" >&2

  response=""
  if [[ "$path" == "/upload" && "$method" == "POST" ]]; then
    # --- File Upload ---
    if (( content_length > 0 )); then
      echo "DEBUG: Reading file body of $content_length bytes." >&2
      body=$(dd bs=1 count="$content_length" 2>/dev/null)
      echo "DEBUG: Body read (length $(echo -n "$body" | wc -c))" >&2
      # Save the body to a unique file (with .tf extension in this example).
      file=$(mktemp "$TEMP_DIR/upload_XXXXXX.tf")
      echo -n "$body" > "$file"
      echo "DEBUG: File saved to '$file'" >&2
      response="File uploaded successfully to $file"
    else
      response="No file content to upload"
    fi
   elif [[ "$path" == "/command" && "$method" == "PUT" ]]; then
    # --- Command Execution ---
    if (( content_length > 0 )); then
      echo "DEBUG: Reading command body of $content_length bytes." >&2
      cmd=$(dd bs=1 count="$content_length" 2>/dev/null)
      echo "DEBUG: Command read: '$cmd'" >&2
      # Change to the temp directory and execute the command.
      output=$(cd "$TEMP_DIR" && eval "$cmd" 2>&1)
      echo "DEBUG: Command output: '$output'" >&2
      response="Command executed. Output:\n$output"
    else
      response="No command provided in the request body"
    fi
  else
    response="Invalid request: method $method, path $path"
  fi

  # Prepare the HTTP response.
  content="$response"
  # Calculate the exact byte count of content.
  content_length_bytes=$(printf "%s" "$content" | wc -c)
  # response_headers=$(printf "HTTP/1.1 200 OK\r\nContent-Length: %d\r\nContent-Type: text/plain\r\n\r\n" "$content_length_bytes")
  response_headers=$(printf "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n")
  # Send the response using printf to avoid extra newlines.
  printf "%s%s" "$response_headers" "$content"
  echo "DEBUG: Response sent." >&2
}

# Export the function so that socat’s subprocess can access it.
export -f handle_request

echo "DEBUG: Starting socat server on port $PORT" >&2
socat TCP-LISTEN:$PORT,reuseaddr,fork EXEC:"bash -c 'handle_request'"
