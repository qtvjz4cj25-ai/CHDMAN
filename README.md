# CHDMAN - Batch CHD Converter

A macOS app for batch converting disc images (CUE/BIN, GDI) to CHD format using [chdman](https://wiki.recalbox.com/en/tutorials/utilities/rom-conversion/chdman).

## About

This project was vibe coded with [Claude](https://claude.ai) (Anthropic's AI assistant) based on a script I originally wrote. The entire SwiftUI app — architecture, UI, parsing, and batch processing — was built collaboratively through conversation with Claude.

## Features

- Batch convert CUE/BIN and GDI disc images to CHD
- Folder scanning with recursive file discovery
- Pause/resume conversions
- Real-time progress tracking and logging
- Configurable chdman binary location
- macOS native SwiftUI interface

## Requirements

- macOS 13.0+
- [chdman](https://wiki.recalbox.com/en/tutorials/utilities/rom-conversion/chdman) binary installed

## Building

Open the project in Xcode or build from the command line:

```bash
swift build
```

## License

MIT
