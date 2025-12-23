# Instinctly Recording Guide

## How to Record Your Screen

### 1. Start Recording

**From Menu Bar:**
1. Click the Instinctly icon in menu bar
2. Choose recording mode:
   - **Record Region**: Select a specific area
   - **Record Window**: Capture a single window
   - **Record Full Screen**: Capture entire screen
   - **Voice Only**: Audio recording only

**From Main Window:**
1. Open Instinctly main window
2. Use the Recording section in sidebar
3. Click on your desired recording mode

### 2. Select Output Format

When the recording panel opens:
1. **Choose Capture Mode** (Region/Window/Full Screen/Voice)
2. **Select Output Format**:
   - **GIF**: Animated image, no audio
   - **MP4**: Standard video format with audio
   - **MOV**: Apple video format with audio
   - **WebM**: Web-optimized video (if available)
   - **M4A**: Audio only (for voice recordings)

### 3. Configure Settings

- **Include Audio**: Toggle to record system audio
- **Include Microphone**: Toggle to record your voice
- **Show Mouse Cursor**: Include cursor in recording
- **Frame Rate**: 15 fps (GIF) or 30/60 fps (video)

### 4. During Recording

- **Red timer** shows recording duration
- **Pause/Resume** button to temporarily stop
- **Stop** button (click again on recording mode) to finish

### 5. After Recording Stops

A **preview panel** will appear showing:
- Video/GIF preview with playback controls
- File size information
- **Save to Library** button (auto-saves)
- **Share** options
- **Show in Finder** to locate file

### Recording Files Location

**Temporary files** (before saving):
```
~/Library/Containers/com.instinctly.app/Data/tmp/
```

**Saved recordings** (in Library):
```
~/Library/Mobile Documents/iCloud~com~instinctly~app/Documents/Library/
```
Or if iCloud not available:
```
~/Library/Application Support/Instinctly/Library/
```

## Troubleshooting

### Black Screen in Recordings

1. **Grant Screen Recording Permission:**
   - System Settings → Privacy & Security → Screen Recording
   - Enable Instinctly
   - Restart the app

2. **Reset Permissions** (if needed):
   ```bash
   tccutil reset ScreenCapture com.instinctly.app
   ```
   Then grant permission again when prompted

### Recording Not Showing in Library

- Recordings auto-save when preview panel appears
- Check the **Recordings** collection in sidebar
- Use **Force Sync** button if using iCloud

### Cannot Select GIF Format

- GIF is only available for screen recording modes
- Not available for Voice Only mode
- GIF files don't include audio

### File Size Too Large

- Use MP4 instead of MOV for smaller files
- Lower frame rate (30 fps instead of 60)
- Use GIF for short clips only (< 30 seconds)

## Tips

1. **Quick Stop**: Click the same recording button again to stop
2. **Preview Loop**: Videos auto-loop in preview for easy review  
3. **Auto-Save**: Recordings save to library automatically
4. **Keyboard Shortcuts**: Coming soon with KeyboardShortcutManager

## Recording Formats Comparison

| Format | Audio | File Size | Best For |
|--------|-------|-----------|----------|
| GIF | No | Large | Short demos, tutorials |
| MP4 | Yes | Medium | General recording |
| MOV | Yes | Large | High quality |
| WebM | Yes | Small | Web sharing |
| M4A | Audio only | Small | Voice notes |