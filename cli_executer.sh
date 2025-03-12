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
  content_type=""
  boundary=""
  echo "DEBUG: Starting header processing." >&2
  while IFS= read -r header_line; do
    header_line="${header_line%%$'\r'}"
    if [ -z "$header_line" ]; then
      break
    fi
    if [[ "$header_line" =~ ^Content-Length:\ ([0-9]+) ]]; then
      content_length=${BASH_REMATCH[1]}
    elif [[ "$header_line" =~ ^Content-Type:\ (.*) ]]; then
      content_type=${BASH_REMATCH[1]}
      if [[ "$content_type" =~ boundary=([^;]+) ]]; then
        boundary=${BASH_REMATCH[1]}
        echo "DEBUG: Found boundary: $boundary" >&2
      fi
    fi
  done
  echo "DEBUG: Finished header processing. Content-Length = $content_length" >&2
  echo "DEBUG: about to process path '$path'" >&2
  response=""
  status_code="200"
  status_message="OK"
  #-- get file handler
  if [[ "$path" =~ ^/output\/(.+)$ ]]; then
    # Extract query parameters
    response_path="${BASH_REMATCH[1]}"
    echo "DEBUG: Response path: '$response_path'" >&2

    # Define the file to serve based on the query parameter
    file_to_serve="$TEMP_DIR/$response_path"

    # Check if file exists
    if [ -f "$file_to_serve" ]; then
      # Read file content
      content=$(cat "$file_to_serve")

      # Set appropriate content type based on file extension
      if [[ "$file_to_serve" == *.html ]]; then
        content_type="text/html"
      elif [[ "$file_to_serve" == *.css ]]; then
        content_type="text/css"
      elif [[ "$file_to_serve" == *.js ]]; then
        content_type="application/javascript"
      elif [[ "$file_to_serve" == *.json ]]; then
        content_type="application/json"
      else
        content_type="text/plain"
      fi

      # Create response with file content
      response="$content"
      echo "DEBUG: Response Content Content-Type: '$content_type'" >&2
      echo "DEBUG: Response: '$response'" >&2
    else
      response="File not found: $file_to_serve"
    fi
  # --- File Upload with custom path and filename ---
  elif [[ "$path" =~ ^/upload\?(.+)$ ]]; then
    # Extract query parameters
    query_params="${BASH_REMATCH[1]}"
    custom_filename=""
    custom_path=""

    # Parse query parameters
    IFS='&' read -ra PARAMS <<<"$query_params"
    for param in "${PARAMS[@]}"; do
      if [[ "$param" =~ ^filename=(.+)$ ]]; then
        custom_filename="${BASH_REMATCH[1]}"
      elif [[ "$param" =~ ^path=(.+)$ ]]; then
        custom_path="${BASH_REMATCH[1]}"
      fi
    done

    if ((content_length > 0)); then
      body=$(dd bs=1 count="$content_length" 2>/dev/null)

      # Use custom path and filename if provided
      if [ -n "$custom_path" ]; then
        target_dir="$TEMP_DIR/$custom_path"
        mkdir -p "$target_dir"
      else
        target_dir="$TEMP_DIR"
      fi

      if [ -n "$custom_filename" ]; then
        file="$target_dir/$custom_filename"
      else
        file=$(mktemp "$target_dir/upload_XXXXXX.tf")
      fi

      # Process multipart form data if applicable
      if [[ -n "$boundary" && "$content_type" == *"multipart/form-data"* ]]; then
        echo "DEBUG: Processing multipart form data with boundary: $boundary" >&2

        # Extract content between boundaries using the actual boundary marker
        boundary_pattern="--${boundary}"

        # Save the raw body for debugging

        intermediate_value=$(echo -n "$body" | sed -n "/${boundary_pattern}/,/${boundary_pattern}--/p")
        echo "DEBUG: Intermediate value: '$intermediate_value'" >&2

        # remove the Content-Disposition header
        intermediate_value=$(echo -n "$intermediate_value" | sed -e "1,/Content-Disposition/d")
        echo "DEBUG: Intermediate value after removing Content-Disposition: '$intermediate_value'" >&2

        # remove the closing boundary
        intermediate_value=$(echo -n "$intermediate_value" | sed -e "/--${boundary}--/d")
        echo "DEBUG: Intermediate value after removing closing boundary: '$intermediate_value'" >&2

        # trim ending empty lines 
        intermediate_value=$(echo -n "$intermediate_value" | sed -e "/^\r$/d")
        echo "DEBUG: Intermediate value after removing ending empty lines: '$intermediate_value'" >&2


        file_content=$(echo -n "$intermediate_value\n\ndafasd" | sed -n "/${boundary_pattern}/,/${boundary_pattern}--/p" | sed -e "1,/Content-Disposition/d" -e "/--${boundary}--/d" -e "1,/^\r$/d")
        echo "DEBUG: Extracted file content: '$intermediate_value'" >&2

        echo "DEBUG: Extracted file content length: $(echo -n "$file_content" | wc -c)" >&2
        echo -n "$intermediate_value" >"$file"
        echo "" >>"$file"
      else
        echo "DEBUG: direct upload"
        echo -n "$body" >"$file"
      fi

      echo "DEBUG: File saved to '$file'" >&2
      response="File uploaded successfully to $file"
    else
      response="No file content to upload"
    fi
  elif [[ "$path" == "/upload" && "$method" == "POST" ]]; then
    # --- File Upload --- // This is the one working
    echo "DEBUG: ~~~~~THIS SHOULD NOT BE HIT~!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! Path: '$path'" >&2
    if ((content_length > 0)); then
      echo "DEBUG: Reading file body of $content_length bytes." >&2
      body=$(dd bs=1 count="$content_length" 2>/dev/null)
      echo "DEBUG: Body: =========== 2'$body'" >&2
      file_content=$(echo -n "$body" | awk -v RS="\r\n\r\n" 'NR==2 {print}' | sed -e 's/\r$//')
      echo "DEBUG: File content: '$file_content'" >&2
      echo "DEBUG: Body read (length $(echo -n "$body" | wc -c))" >&2

      # Save the body to a unique file (with .tf extension in this example).
      file=$(mktemp "$TEMP_DIR/upload_XXXXXX.tf")

      # Process multipart form data if applicable
      if [[ -n "$boundary" && "$content_type" == *"multipart/form-data"* ]]; then
        echo "DEBUG ewerwerewerwetwewe: Processing multipart form data with boundary: $boundary" >&2

        # Extract content between boundaries using the actual boundary marker
        boundary_pattern="--${boundary}"

        # Save the raw body for debugging
        echo -n "$body" >"$file"mp.txt

        # Extract the file content between the first boundary and the closing boundary
        # This preserves all content including any double newlines in the file
        echo "DEBUG: Body  ========== 3: '$body'" >&2
        echo "DEBUG: Boundary pattern: '$boundary_pattern'" >&2
        echo "DEBUG: Body length: $(echo -n "$body" | wc -c)" >&2
        intermidiate_file=$(echo -n "$body" | sed -n "/${boundary_pattern}/,/${boundary_pattern}--/p")
        echo "DEBUG: Intermidiate file: '$intermidiate_file'" >&2
        echo "DEBUG: Intermidiate file length: $(echo -n "$intermidiate_file" | wc -c)" >&2

        file_content=$(echo -n "$body" | sed -n "/${boundary_pattern}/,/${boundary_pattern}--/p" | sed -e "1,/Content-Disposition/d" -e "/--${boundary}--/d" -e "1,/^\r$/d")

        echo "DEBUG: Extracted file content length: $(echo -n "$file_content" | wc -c)" >&2
        echo -n "$file_content" >"$file"
      else

        echo -n "$body" >"$file"mp.txt
        echo -n "$body" >"$file"
      fi

      echo "DEBUG: File saved to '$file'" >&2
      response="File uploaded successfully to $file"
    else
      response="No file content to upload"
    fi
  elif [[ "$path" =~ ^/command\?(.*) && "$method" == "PUT" ]]; then
    # --- Command Execution ---
    if ((content_length > 0)); then
      echo "DEBUG: Reading command body of $content_length bytes." >&2
      cmd=$(dd bs=1 count="$content_length" 2>/dev/null)
      echo "DEBUG: Command read: '$cmd'" >&2
      # Change to the temp directory and execute the command.
      # Extract project type and name from the path
      project_type=$(echo "$path" | grep -oP 'project-type=\K[^&]+')
      project_name=$(echo "$path" | grep -oP 'project-name=\K[^&]+')
      output=$(cd "$TEMP_DIR/$project_type/$project_name" && eval "$cmd" 2>&1)
      echo "DEBUG: Command output: '$output'" >&2
      # make response error, if there is an error in output
      if [[ "$output" == *"Error:"* || $? -ne 0 ]]; then
        status_code="500"
        status_message="Internal Server Error"
        response="Command failed. Output:\n$output"
        echo -n "$response"  > "$TEMP_DIR/$project_type/$project_name/error.html"
      else
        status_code="200"
        status_message="OK"
        response="Command executed. Output:\n$output"
        echo -n "$response" > "$TEMP_DIR/$project_type/$project_name/status.html"
      fi
    else
      status_code="400"
      status_message="Bad Request"
      response="No command provided in the request body"
    fi
  else
    response="Invalid request: method $method, path $path"
  fi

  # Prepare the HTTP response.
  content="$response"
  # Calculate the exact byte count of content.
  content_length_bytes=$(printf "%s" "$content" | wc -c)
  
  # Fix: Properly format the response headers with CRLF separators and add CORS headers
  response_headers=$(printf "HTTP/1.1 %s %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\n\r\n " "$status_code" "$status_message" "$content_type" "$content_length_bytes")
  
  # Send the response using printf to avoid extra newlines.
  printf "%s" "$response_headers"
  printf "\r\n"
  printf "%s" "$content"
  printf "\r\n"
  echo "DEBUG: Response sent: "$content >&2
}

# Export the function so that socat's subprocess can access it.
export -f handle_request

echo "DEBUG: Starting socat server on port $PORT" >&2
socat TCP-LISTEN:$PORT,reuseaddr,fork EXEC:"bash -c 'handle_request'"
