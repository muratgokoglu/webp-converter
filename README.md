<p align="center">
  <img src="docs/icon.png" width="128" alt="WebP Converter icon">
</p>

<h1 align="center">WebP Converter</h1>

<p align="center">A small, native macOS app that batch-converts photos to WebP.</p>

## Features

- Add photos with the file picker or by dragging files and folders onto the window
- Supports JPG, PNG, HEIC/HEIF, TIFF, BMP, GIF and WebP input
- Adjustable quality (1–100, default 75)
- Choose any output folder; existing files are never overwritten (`photo-1.webp`, `photo-2.webp`, …)
- Converts several images in parallel and shows the size before → after for each file
- Respects EXIF orientation, so iPhone photos don't come out rotated
- English and Turkish interface (follows the system language)

## Requirements

- macOS 13 Ventura or later
- [Homebrew](https://brew.sh)
- Xcode Command Line Tools (for building)

## Installation

1. Install the Xcode Command Line Tools, if you don't have them yet:

   ```bash
   xcode-select --install
   ```

2. Install the WebP encoder (`cwebp`), which the app uses for conversion:

   ```bash
   brew install webp
   ```

3. Clone the repository and build the app:

   ```bash
   git clone https://github.com/muratgokoglu/webp-converter-.git
   cd webp-converter-
   ./build.sh
   ```

   This creates `WebP Dönüştürücü.app` in the project folder.

4. Drag the app into your **Applications** folder and open it.

   The app is signed locally (ad-hoc), so since you built it yourself macOS opens it without warnings.

## Usage

1. Click **Add Photos…** or drag photos/folders onto the list.
2. Set the quality with the slider. 75 is a good balance for web use; lower values give smaller files.
3. Click **Output Folder…** and choose where the WebP files should go.
4. Click **Convert to WebP**.

To remove a single file from the list, select it and press Delete.

## Changing the icon

The icon is generated from `logo.svg` by `make_icon.swift`. To change it, edit either file, delete `AppIcon.icns` and run `./build.sh` again.

## How it works

The app is a single SwiftUI file (`WebPConverter.swift`) compiled with `swiftc`, so there is no Xcode project. Each image is decoded with ImageIO (which handles HEIC and orientation), written to a temporary PNG and encoded with `cwebp`.

## License

[PolyForm Noncommercial 1.0.0](LICENSE). You may use, modify and share this software for any noncommercial purpose, such as personal use, study, hobby projects, or use by charities and educational institutions. Commercial use is not permitted; if you'd like to use it commercially, please get in touch.

## Author

[Murat Gökoğlu](https://muratgokoglu.com)
