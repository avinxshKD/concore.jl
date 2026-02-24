# Video Demo Recording Guide

Instructions for recording the concore-jl video demo for GSoC submission.

## Prerequisites

1. **Julia 1.8+** installed and on PATH
2. **Package dependencies** installed:
   ```bash
   cd /path/to/concore-jl
   julia --project=. -e 'using Pkg; Pkg.instantiate()'
   ```
3. **Precompile** (avoids long pauses during recording):
   ```bash
   julia --project=. -e 'using Concore; println("Ready")'
   ```

## Recommended Setup

### Terminal
- **Emulator:** Alacritty, Kitty, or WezTerm (for good rendering)
- **Font size:** 18-20pt monospace
- **Theme:** Dark background, light text (high contrast)
- **Columns:** ~90-100 characters wide
- **Rows:** ~30-35 rows visible

### Screen Recording
- **Resolution:** 1920x1080 (1080p)
- **Frame rate:** 30 fps (sufficient for terminal)
- **Tool:** OBS Studio, SimpleScreenRecorder, or `ffmpeg` with x11grab
- **Audio:** Record narration separately or use OBS audio mixing
- **Format:** MP4 (H.264) for broad compatibility

### OBS Studio Settings
```
Video:
  Base Resolution: 1920x1080
  Output Resolution: 1920x1080
  FPS: 30

Output:
  Recording Format: mp4
  Encoder: x264
  Rate Control: CRF
  CRF: 18 (high quality)

Audio:
  Sample Rate: 48kHz
  Channels: Mono (narration only)
```

## Recording Steps

### 1. Pre-flight Check
```bash
# Verify Julia is available
julia --version

# Verify package loads
julia --project=. -e 'using Concore; println("v$(Concore.VERSION)")'

# Warm up JIT (run once, discard output)
julia --project=. demo/video/repl_demo.jl
julia --project=. demo/run_demo.jl 5
julia --project=. examples/cross_language_test.jl
```

### 2. Start Recording
- Open OBS / recording tool
- Position terminal window to fill the capture area
- Start recording
- Wait 2-3 seconds of silence before starting

### 3. Run the Automated Demo
```bash
# Make executable (one time)
chmod +x demo/video/run_all_demos.sh

# Run the full demo
./demo/video/run_all_demos.sh
```

The script pauses between sections -- use these pauses to:
- Narrate what just happened (see `demo_script.md`)
- Let the viewer absorb the output
- Prepare for the next section

### 4. Alternative: Manual Recording

If you prefer more control, record each section separately:

```bash
# Part 3: Core API
julia --project=. demo/video/repl_demo.jl

# Part 4: Multi-process demo
julia --project=. demo/run_demo.jl 15

# Part 5: Cross-language
julia --project=. examples/cross_language_test.jl

# Part 6: Benchmarks
julia --project=. benchmark/bench_parser.jl
julia --project=. benchmark/bench_io.jl
```

Then stitch clips together in a video editor.

### 5. Post-Processing
- Trim dead air at start and end
- Add title card if desired
- Ensure text is readable at 720p (minimum YouTube quality)
- Export as MP4, target ~50MB or less for easy uploading

## Files in This Directory

| File                | Purpose                                    |
|---------------------|--------------------------------------------|
| `demo_script.md`    | Full narration script and storyboard       |
| `run_all_demos.sh`  | Automated demo runner (press Enter to advance) |
| `repl_demo.jl`      | Scripted API demo (Part 3 of video)        |
| `README.md`         | This file                                  |

## Tips

- **Practice once** before the real recording
- **Pre-run all scripts** so Julia packages are compiled
- **Speak slowly** -- you can always speed up in post
- **Pause at output** -- give viewers time to read terminal output
- **Keep terminal clean** -- use `clear` between sections if needed
- If something fails during recording, just pause, fix it, and re-record
  that section
