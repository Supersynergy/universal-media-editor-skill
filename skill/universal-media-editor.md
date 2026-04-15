---
name: universal-media-editor
description: Universal Media Editor for macOS. Edits audio and video — silence-cut, trim, concat, transcribe, burn captions, denoise, EBU R128 master, stem separate, scene detect, pitch/tempo, subtitle resync, full polish pipeline. Use when the user asks to cut, edit, clean up, caption, transcribe, denoise, normalize loudness, separate stems, remove silence, or polish a video/audio file on a Mac. Sibling skill to universal-media-converter (which handles format conversion).
---

# Universal Media Editor — Skill

You have a `media-edit` CLI plus `me_*` shell functions sourced into the user's shell. These wrap whisper.cpp (Metal), auto-editor, demucs, rubberband, alass, scenedetect, ffmpeg-normalize, and ffmpeg lavfi into a single adaptive interface.

## Quick reference

```bash
media-edit polish <video>              # ✨ full pipeline (THE killer feature)
media-edit recipe <recipe.txt> <file>  # declarative pipeline

# Primitives
me_cut <video>                          # auto silence cut (auto-editor)
me_trim <video> <start> <end>           # precise range cut (stream-copy)
me_concat <out> <in1> <in2>…            # lossless join
me_transcribe <video> [srt|txt|vtt|json]
me_caption <video> [out] [modern|tiktok|cinema]
me_denoise <video>                      # anlmdn (ffmpeg lavfi)
me_master <video> [out] [-16|-14|-23]   # EBU R128 2-pass
me_stems <audio>                        # demucs 4-stem
me_scenes <video>                       # PySceneDetect split
me_pitch <audio> <semitones> <tempo>    # rubberband
me_syncsub <video> <srt>                # alass resync

me_info   # hardware profile + installed tools
```

## What `polish` actually does

`me_polish video.mp4` runs: **auto-editor silence-cut → ffmpeg anlmdn denoise → ffmpeg-normalize EBU R128 (-16 LUFS) → whisper.cpp transcribe → ffmpeg subtitle burn-in (modern style)**. Each step is best-in-class-local as of April 2026.

## Tool routing

| Op              | Tool                       | Why                                          |
|-----------------|----------------------------|----------------------------------------------|
| silence cut     | `auto-editor`              | speech-aware, beats `silenceremove`           |
| transcribe      | `whisper-cli` (whisper.cpp)| Metal on Apple Silicon, 8–16× CPU            |
| stems           | `demucs htdemucs`          | SOTA local separation                        |
| sub resync      | `alass`                    | no-transcript, fixes drift magically          |
| loudness        | `ffmpeg-normalize`         | correct 2-pass EBU R128                       |
| pitch/tempo     | `rubberband`               | SOTA independent manipulation                 |
| scene detect    | `scenedetect`              | content-aware split                          |
| denoise         | `ffmpeg anlmdn`            | non-local-means, best built-in                |
| HDR/DV metadata | `dovi_tool` / `hdr10plus_tool` | only tools that preserve DV through cuts |

## Adaptive

`me_info` shows the hardware profile. Whisper model auto-scales by RAM: tiny.en (<8GB) → base.en (8–16) → medium.en (16–32) → large-v3 (32+).

## When to use

- "cut silence", "remove silences", "trim filler" → `me_cut` / `me_polish`
- "transcribe this", "make subtitles", "generate srt" → `me_transcribe`
- "burn captions", "add subtitles to video" → `me_caption`
- "normalize loudness", "fix volume", "broadcast-ready" → `me_master`
- "remove vocals", "separate stems", "karaoke" → `me_stems`
- "change pitch", "slow down without lowering pitch" → `me_pitch`
- "split video by scenes" → `me_scenes`
- "fix subtitle timing" → `me_syncsub`
- "clean up my podcast", "polish this video" → `me_polish` (full pipeline)
- "custom pipeline", "run these steps" → write a recipe, `me_recipe`

## When NOT to use

- Format conversion (MP4 ↔ MKV, WAV ↔ MP3) → use sibling skill `universal-media-converter` / `conv`
- GUI editing / color grading → suggest Final Cut / DaVinci Resolve
- Cloud workflows → suggest Descript / Veed

## Repo

https://github.com/Supersynergy/universal-media-editor-skill
