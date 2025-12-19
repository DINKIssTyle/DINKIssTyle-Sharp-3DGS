# Sharp Swift 🚀

<p align="center">
  <img src="Docs/Sharp_Swift.gif" alt="Video Demo" width="80%">
</p>

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

---

## 📖 Usage Guide

### 1. Initial Setup (First Run)
When you launch Sharp Swift for the first time, you will see a yellow **"Setup Required"** status.
1. Click the status button.
2. The app will automatically:
    - Create a workspace at `~/Documents/Sharp Swift`.
    - Setup a Python virtual environment.
    - Download necessary machine learning models.
3. Once the indicator turns **Green (Ready)**, you are good to go!

### 2. Importing & Viewing
- **Import**: Simply **drag and drop** an image (`.jpg`, `.png`) or a 3D Scan file (`.ply`) onto the app window.
- **Open**: Or use the **"Open Image / PLY"** button at the top right.

### 3. Viewer Controls
**Top Toolbar:**
- `x`: Close the viewer.
- `⟲`: Reset Camera to default position.
- `Scope`: Toggle "Click-to-Focus" mode.
- `Clock`: Show/Hide the **Animation Timeline**.
- `Speed`: Adjust camera movement sensitivity.
- `FOV`: Adjust Field of View.

**Keyboard Shortcuts:**
- **Movement**: `W` / `S` (Forward/Back), `A` / `D` (Left/Right), `X` / `Z` (Up/Down)
- **Rotation**: `Q` / `E` (Yaw), `C` / `V` (Pitch), `R` / `F` (Roll)
- **Boost**: Hold `Shift` to move faster.
- **General**: `Esc` to close viewer.

**Mouse Controls:**
- **Left Drag**: Orbit / Rotate
- **Right Drag**: Pan
- **Scroll**: Zoom
- **Option + Left Drag**: Roll

### 4. Animation & Export
1. Open the timeline by clicking the **Clock Icon**.
2. **Add Keyframes**: 
   - Move the camera to a desired spot.
   - Click **"Add Key"** on the left.
   - Scrub the slider to a new time position.
   - Move the camera to the next spot.
   - Click **"Add Key"** again.
3. **Preview**: Drag the slider or use Play/Rewind controls.
4. **Export**:
   - Set the **Total Frames** in the center input (`300` by default).
   - Choose **Resolution** (`720p`, `1080p`, etc) and **FPS** on the right.
   - Click **"Export"** to save an `.mp4` video.

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
