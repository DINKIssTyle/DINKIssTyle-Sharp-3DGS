# Sharp Swift 🚀

**Sharp Swift** is a cutting-edge macOS application that transforms static 2D images into immersive 3D Gaussian Splatting scenes. Built with a focus on performance and usability, it combines a robust machine learning pipeline with a high-performance, native Metal renderer.

Whether you are an artist, developer, or 3D enthusiast, Sharp Swift provides a seamless workflow to generate, view, animate, and share 3D moments from a single photo.

## ✨ Key Features

### 🖼️ Image to 3D Conversion
- **Instant Generation**: Simply drag and drop any image to start the conversion process.
- **Automated Pipeline**: The app automatically handles the complex backend logic using `ml-sharp`, transforming 2D pixels into a 3D point cloud of Gaussian splats.

### ⚡️ Native Metal Renderer
- **High Performance**: Custom-built rendering engine using Apple's **Metal API** for buttery smooth performance, specifically optimized for Apple Silicon.
- **True 3D Visualization**: Real-time rendering of millions of splats with correct sorting and blending opacity.

### 🎥 Animation & Timeline
- **Keyframe System**: Create dynamic camera movements by setting keyframes on a timeline.
- **Interpolation**: Smooth camera transitions between keyframes for cinematic effects.
- **Playback Controls**: Play, pause, and scrub through your animation in real-time.

### 📤 Video Export
- **Custom Resolution**: Export your animations in various resolutions, from **360p** up to **4K** (2160p).
- **High-Quality Resizing**: Uses Metal Performance Shaders (MPS) for high-quality downscaling, ensuring crisp results even at lower resolutions (e.g., 720p) on HiDPI displays.
- **Frame Rate Support**: Choose between 24, 30, or 60 FPS for your video output.

### 🛠️ Zero-Config Setup
- **Automatic Environment Management**: First launch automatically sets up a Python virtual environment, installs dependencies, and downloads necessary ML models.
- **Smart Migration**: Intelligently handles workspace folders (`~/Documents/Sharp Swift`), migrating legacy data if detected.

---

## 💻 System Requirements

- **macOS**: macOS Ventura (13.0) or later.
- **Processor**: Apple Silicon (M1/M2/M3) chip highly recommended for ML inference and rendering performance.
- **Python**: Python 3.10+ installed on the system (for the backend ML pipeline).

---

## 🎮 Controls

### 3D View Navigation
- **Rotate/Orbit**: Left Click + Drag
- **Pan**: Right Click + Drag (or Two-finger drag)
- **Zoom**: Scroll Wheel (or Pinch gesture)
- **Roll**: Option + Left Click + Drag

### Timeline
- **Add Keyframe**: Adds the current camera view as a keyframe at the current time.
- **Del Keyframe**: Removes the keyframe at the current cursor position.
- **Scrubbing**: Drag the slider handle to preview the animation.

---

## 🏗️ Building from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/DINKIssTyle-Sharp-3DGS/Sharp-Swift.git
   cd Sharp-Swift
   ```

2. Run the build script:
   ```bash
   ./build.sh
   ```
   This script will compile the Swift code, handle assets, and generate `Sharp Swift.app`.

3. Run the App:
   ```bash
   open "./Sharp Swift.app"
   ```

---

## 🧩 Architecture

- **Frontend**: Swift (AppKit/SwiftUI)
- **Rendering**: MetalKit (Custom Shader Pipeline)
- **Backend (ML)**: Python (ml-sharp), integrated via `ProcessRunner`
- **Video Encoding**: AVFoundation

---

## 📜 License

This project is intended for educational and research purposes. Please refer to the `ml-sharp` license for details regarding the underlying machine learning model usage.
