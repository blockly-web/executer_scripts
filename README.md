# My Tool

This repository contains a shell script that starts an HTTP server using `socat`.

---
It supporting companion for BlockCode project
`https://github.com/blockly-web/blockly`
`https://blockcode.web.app/#/`

The script uses a temporary directory for processing files.

## Prerequisites

- Bash (version 4 or above)
- [`socat`](http://www.dest-unreach.org/socat/)  
  _(Install on Debian/Ubuntu with `sudo apt-get install socat`)_  
- [`curl`](https://curl.se/) for the installation script

## Installation

1. **Download and run the installation script:**

   ```bash  
   curl -fsSL https://raw.githubusercontent.com/blockly-web/executer_scripts/main/install.sh | bash
   ```

