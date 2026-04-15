#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════
#  media-edit — Universal Media Editor (+ Skill)
#  Cut · Transcribe · Caption · Denoise · Master · Separate · Polish
#  https://github.com/Supersynergy/universal-media-editor-skill
#  MIT License · by Maxim Supersynergy
# ════════════════════════════════════════════════════════════════

: "${ME_TIER:=}" "${ME_NCPU:=}" "${ME_MEM_GB:=}" "${ME_VTB:=}"
: "${ME_STATS_FILE:=$HOME/.media-edit/stats}"
: "${ME_WHISPER_MODEL:=base.en}"   # tiny|base|small|medium|large-v3
: "${ME_SOUND:=1}"

_me_init() {
  [ -n "$ME_TIER" ] && return
  local chip
  chip=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
  ME_NCPU=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
  ME_MEM_GB=$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0f", $0/1073741824}')
  [ -z "$ME_MEM_GB" ] && ME_MEM_GB=8

  if   [[ "$chip" == *Ultra* ]]; then ME_TIER="ultra"
  elif [[ "$chip" == *Max*   ]]; then ME_TIER="max"
  elif [[ "$chip" == *Pro*   ]]; then ME_TIER="pro"
  elif [[ "$chip" =~ M[1-9]  ]]; then ME_TIER="base"
  else                                ME_TIER="intel"
  fi

  ffmpeg -hide_banner -encoders 2>/dev/null | grep -q videotoolbox && ME_VTB=1 || ME_VTB=0

  # Adaptive Whisper model by RAM tier
  if [ -z "$ME_WHISPER_MODEL" ] || [ "$ME_WHISPER_MODEL" = "auto" ]; then
    if   [ "$ME_MEM_GB" -ge 32 ]; then ME_WHISPER_MODEL="large-v3"
    elif [ "$ME_MEM_GB" -ge 16 ]; then ME_WHISPER_MODEL="medium.en"
    elif [ "$ME_MEM_GB" -ge 8  ]; then ME_WHISPER_MODEL="base.en"
    else                               ME_WHISPER_MODEL="tiny.en"
    fi
  fi

  export ME_TIER ME_NCPU ME_MEM_GB ME_VTB ME_WHISPER_MODEL
}

_me_have() { command -v "$1" >/dev/null 2>&1; }
_me_need() { _me_have "$1" || { echo "❌ Need '$1'. Install: $2" >&2; return 1; }; }

_me_track() {
  local op="$1"
  mkdir -p "$(dirname "$ME_STATS_FILE")"
  [ -f "$ME_STATS_FILE" ] || echo "total=0" > "$ME_STATS_FILE"
  # shellcheck disable=SC1090
  source "$ME_STATS_FILE"
  total=$((${total:-0} + 1))
  printf 'total=%d\n' "$total" > "$ME_STATS_FILE"
  [ -n "$op" ] && echo "$(date +%s) $op" >> "$HOME/.media-edit/log" 2>/dev/null
}

_me_done() {
  [ "$ME_SOUND" = "1" ] && _me_have afplay && \
    (afplay /System/Library/Sounds/Glass.aiff 2>/dev/null &)
}

# ════════════════════════════════════════════════════════════════
#  INFO
# ════════════════════════════════════════════════════════════════
me_info() {
  _me_init
  cat <<EOF
🎬 Universal Media Editor — Adaptive Profile
   Chip:           $ME_TIER ($(sysctl -n machdep.cpu.brand_string 2>/dev/null))
   Cores:          $ME_NCPU
   RAM:            ${ME_MEM_GB} GB
   VideoToolbox:   $([ "$ME_VTB" = "1" ] && echo '✅' || echo '❌')
   Whisper model:  $ME_WHISPER_MODEL

Tools:
$(for t in ffmpeg whisper-cli auto-editor demucs rubberband sox scenedetect ffmpeg-normalize alass dovi_tool hdr10plus_tool mpv mediainfo; do
    _me_have "$t" && printf '   ✅ %s\n' "$t" || printf '   ❌ %s\n' "$t"
  done)
EOF
}

# ════════════════════════════════════════════════════════════════
#  CUT — silence-aware auto-cut via auto-editor
# ════════════════════════════════════════════════════════════════
me_cut() {
  _me_init
  local input="$1" output="${2:-${1%.*}_cut.${1##*.}}"
  [ -f "$input" ] || { echo "❌ Not found: $input" >&2; return 1; }
  _me_need auto-editor "uv tool install auto-editor" || return 1
  echo "✂️  Cut silence (auto-editor) → $output"
  auto-editor "$input" -o "$output" --no-open
  _me_track cut; _me_done
  echo "✅ $output"
}

# ════════════════════════════════════════════════════════════════
#  TRIM — precise time-range cut, stream copy when possible
# ════════════════════════════════════════════════════════════════
me_trim() {
  _me_init
  local input="$1" start="$2" end="$3" output="${4:-${1%.*}_trim.${1##*.}}"
  [ -f "$input" ] || { echo "❌ Not found: $input" >&2; return 1; }
  [ -z "$start" ] || [ -z "$end" ] && { echo "Usage: me_trim <in> <start> <end> [out]"; return 1; }
  echo "✂️  Trim $start → $end (copy) → $output"
  ffmpeg -y -ss "$start" -to "$end" -i "$input" -c copy -avoid_negative_ts make_zero "$output" 2>&1 | tail -2
  _me_track trim; _me_done
  echo "✅ $output"
}

# ════════════════════════════════════════════════════════════════
#  CONCAT — join multiple clips losslessly when compatible
# ════════════════════════════════════════════════════════════════
me_concat() {
  _me_init
  local output="$1"; shift
  [ -z "$output" ] || [ $# -lt 2 ] && { echo "Usage: me_concat <out.mp4> <in1> <in2> [..]"; return 1; }
  local list; list=$(mktemp)
  local f
  for f in "$@"; do
    [ -f "$f" ] || { echo "❌ Not found: $f" >&2; return 1; }
    printf "file '%s'\n" "$(realpath "$f")" >> "$list"
  done
  echo "🔗 Concat $# clips → $output"
  ffmpeg -y -f concat -safe 0 -i "$list" -c copy "$output" 2>&1 | tail -2
  rm -f "$list"
  _me_track concat; _me_done
  echo "✅ $output"
}

# ════════════════════════════════════════════════════════════════
#  TRANSCRIBE — whisper.cpp Metal (native) or faster-whisper fallback
# ════════════════════════════════════════════════════════════════
me_transcribe() {
  _me_init
  local input="$1" format="${2:-srt}"  # srt|txt|vtt|json
  local base="${1%.*}"
  [ -f "$input" ] || { echo "❌ Not found: $input" >&2; return 1; }

  local wav; wav="$(mktemp).wav"
  ffmpeg -y -i "$input" -ar 16000 -ac 1 -c:a pcm_s16le "$wav" 2>/dev/null

  if _me_have whisper-cli; then
    local model="$HOME/.cache/whisper.cpp/ggml-${ME_WHISPER_MODEL}.bin"
    mkdir -p "$(dirname "$model")"
    if [ ! -f "$model" ]; then
      echo "📥 Downloading whisper.cpp model: $ME_WHISPER_MODEL"
      curl -fsSL "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${ME_WHISPER_MODEL}.bin" -o "$model"
    fi
    echo "📝 Transcribe (whisper.cpp, Metal) model=$ME_WHISPER_MODEL → ${base}.${format}"
    local flag
    case "$format" in
      srt)  flag="--output-srt" ;;
      vtt)  flag="--output-vtt" ;;
      txt)  flag="--output-txt" ;;
      json) flag="--output-json" ;;
      *)    flag="--output-srt" ;;
    esac
    whisper-cli -m "$model" -f "$wav" $flag -of "$base" 2>&1 | grep -E "whisper_|\[" | tail -5
  elif _me_have uvx; then
    echo "📝 Transcribe (faster-whisper via uvx)"
    uvx faster-whisper-xxl "$wav" --model "$ME_WHISPER_MODEL" --output_format "$format" -o "$(dirname "$input")" 2>&1 | tail -5
  else
    echo "❌ Need whisper-cli (brew install whisper-cpp) or uvx" >&2
    rm -f "$wav"; return 1
  fi
  rm -f "$wav"
  _me_track transcribe; _me_done
  echo "✅ ${base}.${format}"
}

# ════════════════════════════════════════════════════════════════
#  CAPTION — transcribe → burn styled ASS subtitles into video
# ════════════════════════════════════════════════════════════════
me_caption() {
  _me_init
  local input="$1" output="${2:-${1%.*}_captioned.mp4}" style="${3:-modern}"
  [ -f "$input" ] || { echo "❌ Not found: $input" >&2; return 1; }

  local base="${input%.*}"
  [ -f "${base}.srt" ] || me_transcribe "$input" srt
  [ -f "${base}.srt" ] || { echo "❌ Transcription failed"; return 1; }

  # Style presets (ASS override)
  local force_style
  case "$style" in
    modern)  force_style="Fontname=Helvetica Neue,Fontsize=28,PrimaryColour=&H00FFFFFF,OutlineColour=&H80000000,BorderStyle=1,Outline=2,Shadow=1,Alignment=2,MarginV=60" ;;
    tiktok)  force_style="Fontname=Arial Black,Fontsize=36,PrimaryColour=&H00FFFF00,OutlineColour=&HFF000000,BorderStyle=1,Outline=3,Shadow=0,Alignment=2,MarginV=120" ;;
    cinema)  force_style="Fontname=Helvetica,Fontsize=22,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,BorderStyle=1,Outline=1,Shadow=0,Alignment=2,MarginV=40" ;;
    *)       force_style="Fontname=Helvetica Neue,Fontsize=28" ;;
  esac

  echo "🎨 Burn captions ($style) → $output"
  if [ "$ME_VTB" = "1" ]; then
    ffmpeg -y -i "$input" -vf "subtitles=${base}.srt:force_style='${force_style}'" \
      -c:v hevc_videotoolbox -b:v 4000k -c:a copy "$output" 2>&1 | tail -2
  else
    ffmpeg -y -i "$input" -vf "subtitles=${base}.srt:force_style='${force_style}'" \
      -c:v libx264 -crf 23 -preset medium -c:a copy "$output" 2>&1 | tail -2
  fi
  _me_track caption; _me_done
  echo "✅ $output"
}

# ════════════════════════════════════════════════════════════════
#  DENOISE — ffmpeg lavfi anlmdn (best built-in denoiser)
# ════════════════════════════════════════════════════════════════
me_denoise() {
  _me_init
  local input="$1" output="${2:-${1%.*}_denoised.${1##*.}}"
  [ -f "$input" ] || { echo "❌ Not found: $input" >&2; return 1; }
  echo "🔇 Denoise (anlmdn) → $output"
  ffmpeg -y -i "$input" -af "highpass=f=80,anlmdn=s=7:p=0.002:r=0.01,lowpass=f=12000" \
    -c:v copy "$output" 2>&1 | tail -2
  _me_track denoise; _me_done
  echo "✅ $output"
}

# ════════════════════════════════════════════════════════════════
#  MASTER — two-pass EBU R128 loudness normalize
# ════════════════════════════════════════════════════════════════
me_master() {
  _me_init
  local input="$1" output="${2:-${1%.*}_mastered.${1##*.}}"
  local target="${3:--16}"  # -16 LUFS YouTube, -14 Spotify, -23 EBU TV
  [ -f "$input" ] || { echo "❌ Not found: $input" >&2; return 1; }
  if _me_have ffmpeg-normalize; then
    echo "🎚  Master to ${target} LUFS (ffmpeg-normalize, 2-pass EBU R128) → $output"
    ffmpeg-normalize "$input" -o "$output" -f -t "$target" --loudness-range-target 7 --true-peak -1 -c:a aac -b:a 256k 2>&1 | tail -3
  else
    echo "🎚  Master to ${target} LUFS (ffmpeg loudnorm 1-pass) → $output"
    ffmpeg -y -i "$input" -af "loudnorm=I=${target}:TP=-1:LRA=7" -c:v copy "$output" 2>&1 | tail -2
  fi
  _me_track master; _me_done
  echo "✅ $output"
}

# ════════════════════════════════════════════════════════════════
#  STEMS — demucs 4-stem separation (vocals/drums/bass/other)
# ════════════════════════════════════════════════════════════════
me_stems() {
  _me_init
  local input="$1" outdir="${2:-stems}"
  [ -f "$input" ] || { echo "❌ Not found: $input" >&2; return 1; }
  _me_need demucs "uv tool install demucs" || return 1
  echo "🎛  Stem separation (demucs htdemucs) → $outdir/"
  demucs -n htdemucs -o "$outdir" "$input"
  _me_track stems; _me_done
  echo "✅ $outdir/htdemucs/$(basename "${input%.*}")/"
}

# ════════════════════════════════════════════════════════════════
#  SCENES — auto-split a video at scene cuts (PySceneDetect)
# ════════════════════════════════════════════════════════════════
me_scenes() {
  _me_init
  local input="$1" threshold="${2:-27}"
  [ -f "$input" ] || { echo "❌ Not found: $input" >&2; return 1; }
  _me_need scenedetect "pipx install 'scenedetect[opencv]'" || return 1
  echo "🎞  Scene detect (threshold=$threshold) → scenes/"
  scenedetect -i "$input" -o scenes detect-content -t "$threshold" split-video
  _me_track scenes; _me_done
  echo "✅ scenes/"
}

# ════════════════════════════════════════════════════════════════
#  PITCH — rubberband time/pitch preserving
# ════════════════════════════════════════════════════════════════
me_pitch() {
  _me_init
  local input="$1" semitones="${2:-0}" tempo="${3:-1.0}" output="${4:-${1%.*}_pitched.${1##*.}}"
  [ -f "$input" ] || { echo "❌ Not found: $input" >&2; return 1; }
  _me_need rubberband "brew install rubberband" || return 1
  echo "🎵 Pitch $semitones st, tempo ${tempo}x (rubberband) → $output"
  rubberband -p "$semitones" -T "$tempo" "$input" "$output"
  _me_track pitch; _me_done
  echo "✅ $output"
}

# ════════════════════════════════════════════════════════════════
#  SYNCSUB — fix subtitle timing drift without transcript (alass)
# ════════════════════════════════════════════════════════════════
me_syncsub() {
  _me_init
  local video="$1" subs="$2" output="${3:-${subs%.*}_synced.${subs##*.}}"
  [ -f "$video" ] && [ -f "$subs" ] || { echo "Usage: me_syncsub <video> <subs.srt> [out.srt]"; return 1; }
  _me_need alass "brew install alass" || return 1
  echo "🔧 Resync subs (alass) → $output"
  alass "$video" "$subs" "$output"
  _me_track syncsub; _me_done
  echo "✅ $output"
}

# ════════════════════════════════════════════════════════════════
#  POLISH — THE killer feature: full pipeline
#  raw video → cut silences → denoise → master → transcribe → caption
# ════════════════════════════════════════════════════════════════
me_polish() {
  _me_init
  local input="$1" output="${2:-${1%.*}_polished.mp4}" style="${3:-modern}"
  [ -f "$input" ] || { echo "❌ Not found: $input" >&2; return 1; }

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "✨ POLISH PIPELINE — $input"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  local work; work=$(mktemp -d)
  local cur="$input"

  if _me_have auto-editor; then
    echo "[1/5] ✂️  silence cut"
    auto-editor "$cur" -o "$work/1_cut.mp4" --no-open >/dev/null 2>&1 && cur="$work/1_cut.mp4"
  else
    echo "[1/5] ⏭  skip cut (auto-editor missing)"
  fi

  echo "[2/5] 🔇 denoise (anlmdn)"
  ffmpeg -y -i "$cur" -af "highpass=f=80,anlmdn=s=7:p=0.002:r=0.01,lowpass=f=12000" \
    -c:v copy "$work/2_dn.mp4" 2>/dev/null && cur="$work/2_dn.mp4"

  echo "[3/5] 🎚  loudness normalize (-16 LUFS)"
  if _me_have ffmpeg-normalize; then
    ffmpeg-normalize "$cur" -o "$work/3_norm.mp4" -f -t -16 --loudness-range-target 7 -c:a aac -b:a 256k >/dev/null 2>&1 && cur="$work/3_norm.mp4"
  else
    ffmpeg -y -i "$cur" -af "loudnorm=I=-16:TP=-1:LRA=7" -c:v copy "$work/3_norm.mp4" 2>/dev/null && cur="$work/3_norm.mp4"
  fi

  echo "[4/5] 📝 transcribe (whisper.cpp Metal)"
  cp "$cur" "$work/pre_caption.mp4"
  ( cd "$work" && me_transcribe pre_caption.mp4 srt >/dev/null 2>&1 )

  echo "[5/5] 🎨 burn captions ($style)"
  if [ -f "$work/pre_caption.srt" ]; then
    local fs
    case "$style" in
      tiktok) fs="Fontname=Arial Black,Fontsize=36,PrimaryColour=&H00FFFF00,OutlineColour=&HFF000000,BorderStyle=1,Outline=3,Alignment=2,MarginV=120" ;;
      cinema) fs="Fontname=Helvetica,Fontsize=22,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,Outline=1,Alignment=2,MarginV=40" ;;
      *)      fs="Fontname=Helvetica Neue,Fontsize=28,PrimaryColour=&H00FFFFFF,OutlineColour=&H80000000,Outline=2,Shadow=1,Alignment=2,MarginV=60" ;;
    esac
    if [ "$ME_VTB" = "1" ]; then
      ffmpeg -y -i "$work/pre_caption.mp4" -vf "subtitles=$work/pre_caption.srt:force_style='${fs}'" \
        -c:v hevc_videotoolbox -b:v 4000k -c:a copy "$output" 2>/dev/null
    else
      ffmpeg -y -i "$work/pre_caption.mp4" -vf "subtitles=$work/pre_caption.srt:force_style='${fs}'" \
        -c:v libx264 -crf 23 -preset medium -c:a copy "$output" 2>/dev/null
    fi
  else
    cp "$cur" "$output"
  fi

  rm -rf "$work"
  _me_track polish; _me_done
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "✅ Polished → $output"
}

# ════════════════════════════════════════════════════════════════
#  RECIPE — declarative YAML-ish pipeline
#  Lines: "op arg1 arg2" — run in order, $_ is current file
# ════════════════════════════════════════════════════════════════
me_recipe() {
  _me_init
  local recipe="$1" input="$2"
  [ -f "$recipe" ] && [ -f "$input" ] || { echo "Usage: me_recipe <recipe.txt> <input>"; return 1; }
  echo "📋 Recipe: $recipe"
  local cur="$input" step=0
  while IFS= read -r line; do
    line="${line%%#*}"; line="${line## }"; line="${line%% }"
    [ -z "$line" ] && continue
    step=$((step + 1))
    local op arg1 arg2
    read -r op arg1 arg2 <<< "$line"
    local next="${cur%.*}_s${step}.${cur##*.}"
    echo "  [$step] $op $arg1 $arg2"
    case "$op" in
      cut)        me_cut "$cur" "$next" >/dev/null && cur="$next" ;;
      trim)       me_trim "$cur" "$arg1" "$arg2" "$next" >/dev/null && cur="$next" ;;
      denoise)    me_denoise "$cur" "$next" >/dev/null && cur="$next" ;;
      master)     me_master "$cur" "$next" "${arg1:--16}" >/dev/null && cur="$next" ;;
      transcribe) me_transcribe "$cur" "${arg1:-srt}" >/dev/null ;;
      caption)    next="${cur%.*}_cap.mp4"; me_caption "$cur" "$next" "${arg1:-modern}" >/dev/null && cur="$next" ;;
      pitch)      me_pitch "$cur" "${arg1:-0}" "${arg2:-1.0}" "$next" >/dev/null && cur="$next" ;;
      *)          echo "  ⚠ unknown op: $op" ;;
    esac
  done < "$recipe"
  echo "✅ Final: $cur"
}

# ════════════════════════════════════════════════════════════════
#  Easter eggs 🥚
# ════════════════════════════════════════════════════════════════
me_stats() {
  [ -f "$ME_STATS_FILE" ] || { echo "No stats yet. Edit something first!"; return; }
  source "$ME_STATS_FILE"
  echo "🎬 Lifetime media-edit ops: ${total:-0}"
  [ -f "$HOME/.media-edit/log" ] && echo "Most-used:" && \
    awk '{print $2}' "$HOME/.media-edit/log" | sort | uniq -c | sort -rn | head -5
}

me_joke() {
  local jokes=(
    "Why did the editor break up with ffmpeg?    Too many arguments."
    "A director, a sound engineer, and a colorist walk into a bar. They spend 3 hours arguing about which LUT to use."
    "whisper.cpp walks into a studio. It transcribes the silence."
    "I told demucs my problems. It separated me into four people."
    "Dolby Vision metadata is just lies we agree to believe."
    "rubberband can change my pitch. I wish it could change my mind."
  )
  echo "${jokes[$RANDOM % ${#jokes[@]}]}"
}

me_zen() {
  local zen=(
    "Cut twice. Publish once."
    "Silence is a performance. Respect it, or cut it."
    "Every LUT is a lie that feels true."
    "The best edit is invisible."
    "Loudness is not the same as presence."
  )
  echo "🧘 ${zen[$RANDOM % ${#zen[@]}]}"
}

me_help() {
  cat <<'EOF'
🎬 media-edit — Universal Media Editor

PIPELINE
  me_polish <video> [out] [style]   ✨ full pipeline: cut→denoise→master→caption
  me_recipe <recipe.txt> <input>    📋 run a declarative recipe

PRIMITIVES
  me_cut <video> [out]              ✂️  auto silence cut (auto-editor)
  me_trim <video> <start> <end>     ✂️  precise range cut (stream copy)
  me_concat <out> <in1> <in2>…      🔗 lossless concat
  me_transcribe <video> [srt|txt]   📝 whisper.cpp (Metal on Apple Silicon)
  me_caption <video> [out] [style]  🎨 burn styled captions (modern|tiktok|cinema)
  me_denoise <video> [out]          🔇 anlmdn denoise
  me_master <video> [out] [LUFS]    🎚  EBU R128 loudness normalize
  me_stems <audio> [outdir]         🎛  demucs 4-stem separation
  me_scenes <video> [threshold]     🎞  PySceneDetect auto-split
  me_pitch <audio> [st] [tempo]     🎵 rubberband pitch/tempo
  me_syncsub <video> <srt>          🔧 alass re-sync subtitles

INFO & FUN
  me_info                           hardware profile + tool check
  me_stats                          lifetime ops counter
  me_joke / me_zen                  🥚
  me_help                           this screen

ENV
  ME_WHISPER_MODEL=auto|tiny.en|base.en|medium.en|large-v3
  ME_SOUND=0                        silence completion chime
EOF
}

# Router for `media-edit <cmd>` style CLI invocation
media-edit() {
  local cmd="$1"; shift || true
  case "$cmd" in
    ""|-h|--help|help) me_help ;;
    info)       me_info ;;
    stats)      me_stats ;;
    joke)       me_joke ;;
    zen)        me_zen ;;
    cut)        me_cut "$@" ;;
    trim)       me_trim "$@" ;;
    concat)     me_concat "$@" ;;
    transcribe) me_transcribe "$@" ;;
    caption)    me_caption "$@" ;;
    denoise)    me_denoise "$@" ;;
    master)     me_master "$@" ;;
    stems)      me_stems "$@" ;;
    scenes)     me_scenes "$@" ;;
    pitch)      me_pitch "$@" ;;
    syncsub)    me_syncsub "$@" ;;
    polish)     me_polish "$@" ;;
    recipe)     me_recipe "$@" ;;
    *)          echo "Unknown command: $cmd"; me_help; return 1 ;;
  esac
}
