# CLI Executer

A lightweight HTTP server that handles file uploads and command execution, designed as a companion for the BlockCode project.

- Project: https://github.com/blockly-web/blockly
- Demo: https://blockcode.web.app/#/

## Features

- File upload with custom path and filename support
- Command execution in an isolated temporary directory
- Simple HTTP interface
- Debug logging

## Prerequisites

- Bash (version 4 or above)
- [`socat`](http://www.dest-unreach.org/socat/)  
  _(Install on Debian/Ubuntu with `sudo apt-get install socat`)_  
- [`curl`](https://curl.se/) for the installation script

## Installation

### Automatic Installation

```bash
curl -fsSL https://raw.githubusercontent.com/blockly-web/executer_scripts/main/install.sh | bash
```

### Manual Installation

1. Download the script:
```bash
wget https://github.com/blockly-web/executer_scripts/releases/download/v1.0.1/cli_executer.sh
```

2. Make it executable:
```bash
chmod +x cli_executer.sh
```

3. Move to system path (optional):
```bash
sudo mv cli_executer.sh /usr/local/bin/cli_executer
```

## Usage

### Starting the Server

```bash
cli_executer
```

The server will start on port 8080 by default and create a `temp` directory in the current working directory.

### File Upload

You can upload files in several ways:

1. Basic upload (auto-generated filename):
```bash
curl -X POST http://localhost:8080/upload --data-binary @yourfile.tf
```

2. Upload with custom filename:
```bash
curl -X POST "http://localhost:8080/upload?filename=myfile.tf" --data-binary @yourfile.tf
```

3. Upload to custom path:
```bash
curl -X POST "http://localhost:8080/upload?path=subfolder" --data-binary @yourfile.tf
```

4. Upload with both custom filename and path:
```bash
curl -X POST "http://localhost:8080/upload?filename=myfile.tf&path=subfolder" --data-binary @yourfile.tf
```

### Command Execution

Execute commands in the temporary directory:

```bash
curl -X PUT http://localhost:8080/command --data-binary "ls -la"
```

## Security Considerations

- The server is designed for local use and doesn't implement authentication
- All operations are confined to the `temp` directory
- Use in trusted environments only
- Consider network security implications when exposing the port

## Contributing

Feel free to open issues or submit pull requests on GitHub.

## License

[License details here]

