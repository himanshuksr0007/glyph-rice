#!/usr/bin/env bash
# Galaga: installs everything on a clean Arch and links the configs from this repo.
#   ./install.sh                   guided: every question first (extras, file manager, login
#                                  screen, boot screen), one password, then it runs to the end
#   ./install.sh --dry-run         the guided flow, printing what it would do; changes nothing
#   ./install.sh --with telegram   same without the questions (--with "" -- just the rice itself)
#   ./install.sh --browsers zen,firefox
#                                  which browsers to install (a question in the guided flow;
#                                  firefox pre-ticked, untick all -- none; --browsers "" -- none)
#   ./install.sh --update          get the newest version of the rice, then refresh what changed
#   ./install.sh --uninstall       take the links away, put the old files and login screen back
#   ./install.sh --fix-plasma      from KDE Plasma: Wi-Fi passwords out of KDE Wallet, autostart guards
#   ./install.sh --links           symlinks only (on an already configured system)
#   ./install.sh --greeter         boot login: greetd with the galaga face -- REPLACES the current
#                                  display manager (sddm/...); separate on purpose, prints its rollback
#   ./install.sh --quiet-boot      a silent boot: the kernel line goes quiet, the splash comes up,
#                                  and the greeter's and the session's output goes to log files
#                                  instead of the console (--dry-run says what it would do)
#   ./install.sh --no-quiet-boot   undo --quiet-boot -- the boot text comes back
set -euo pipefail

DOTS="$(cd "$(dirname "$0")" && pwd)"
BACKUP="$HOME/.dots-backup-$(date +%F_%H-%M-%S)"

DRY=0
run() { # the guided flow's changes go through here, so --dry-run can't touch anything
    if [ "$DRY" = 1 ]; then printf '  would run: %s\n' "$*"; else "$@"; fi
}
note() { printf '  %s\n' "$*"; }

PACMAN=(
    # base (cmake/meson: hyprpm builds the plugins from source)
    base-devel git curl jq python cmake meson
    # session (hyprpm is its own package -- it no longer ships inside hyprland)
    hyprland hyprpm hypridle hyprsunset hyprpicker xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    sddm quickshell qt6-multimedia polkit-gnome gnome-keyring geoclue upower xdg-user-dirs
    # audio, network, bluetooth (pipewire-audio carries the SPA Bluetooth plugins on
    # Arch -- there is no libspa-0.2-bluetooth package here; a wrong name aborts pacman)
    pipewire pipewire-pulse pipewire-alsa pipewire-audio wireplumber networkmanager bluez bluez-utils power-profiles-daemon
    # utilities called by keybinds and the shell
    brightnessctl ddcutil playerctl wl-clipboard cliphist grim slurp swappy imagemagick libvips libqalculate
    # drives: mounting (udisks2), the file manager's sidebar and phones (gvfs), mounting by itself (udiskie), common formats
    udisks2 gvfs gvfs-mtp gvfs-gphoto2 udiskie ntfs-3g exfatprogs dosfstools
    tesseract tesseract-data-eng zbar # shot: grab text (OCR) + scan QR/barcode
    gpu-screen-recorder ydotool libnotify trash-cli
    # terminal and console
    kitty fish starship fastfetch btop cava eza zoxide direnv
    # apps from variables.lua
    thunar pavucontrol
    # fonts (cjk -- kaomoji in Charms), icons (Papirus-Dark -- base for the Rice folder theme), dark base for gtk.css
    ttf-jetbrains-mono-nerd noto-fonts noto-fonts-cjk noto-fonts-emoji papirus-icon-theme adw-gtk-theme
)

AUR=(
    qtengine darkly-bin bibata-cursor-theme-bin
    localsend-bin # LocalSend -- Super+Ctrl+S sends the clipboard, Nautilus right-click (with nautilus-python)
)

# greeter only (./install.sh --greeter). The compositor is the session's own Hyprland
# (stripped config in config/greetd/), already installed above -- greetd is the only addition
GREETER_PACMAN=(greetd)

# browsers are a choice of their own (browsers() below asks, --browsers answers): key -> packages.
# Nothing is forced -- until this was asked, zen-browser-bin sat in the AUR list for everyone.
# The first one picked also becomes the Super+W browser (browser_bind() writes it to user.lua).
declare -A BROWSER=(
    [firefox]="firefox"        # pacman
    [zen]="zen-browser-bin"    # AUR
    [chromium]="chromium"      # pacman
    [brave]="brave-bin"        # AUR
    [vivaldi]="vivaldi"        # pacman
)
declare -A BROWSER_CMD=( [firefox]=firefox [zen]=zen-browser [chromium]=chromium [brave]=brave [vivaldi]=vivaldi )

# optional, like caelestia's optional components. What the special-workspace keybinds open -- apps in hypr/variables.lua
declare -A EXTRA=(
    [telegram]="telegram-desktop"                                        # Super+D
    [spotify]="spotify-launcher spicetify-cli spicetify-marketplace-bin" # Super+M
    [clash]="clash-verge-rev-bin"                                        # VPN panel, Super+P
    [pywalfox]="python-pywalfox"                                         # Firefox follows the palette (with the Pywalfox add-on)
    [warp]="cloudflare-warp-bin"                                         # Cloudflare WARP: warp-svc daemon, warp-cli, warp-taskbar tray
    [overskride]="overskride-bin"                                        # a full Bluetooth manager next to the shell's quick panel
)

G=config/quickshell/galaga
# repo path -> path in $HOME
LINKS=(
    "config/hypr                                .config/hypr"
    "config/nautilus-python/localsend.py        .local/share/nautilus-python/extensions/localsend.py"
    "$G                                         .config/quickshell/galaga"
    "config/quickshell/rice                     .config/quickshell/rice"
    "config/quickshell/rice/rice                .local/bin/rice"
    "config/kitty                               .config/kitty"
    "config/qtengine                            .config/qtengine"
    "$G/term/qtengine.colors                    .config/qtengine.colors"
    "$G/term/starship.toml                      .config/starship.toml"
    "$G/term/fastfetch                          .config/fastfetch"
    "$G/term/btop                               .config/btop"
    "$G/term/cava                               .config/cava"
    "$G/term/gtk-3.0/gtk.css                    .config/gtk-3.0/gtk.css"
    "$G/term/gtk-4.0/gtk.css                    .config/gtk-4.0/gtk.css"
    "$G/term/gtk-3.0/settings.ini               .config/gtk-3.0/settings.ini"
    "$G/term/gtk-4.0/settings.ini               .config/gtk-4.0/settings.ini"
    "$G/term/window-buttons                     .config/gtk-3.0/window-buttons"
    "$G/term/window-buttons                     .config/gtk-4.0/window-buttons"
    "config/pipewire/pipewire.conf.d/52-galaga-eq.conf .config/pipewire/pipewire.conf.d/52-galaga-eq.conf"
    "config/fish/config.fish                    .config/fish/config.fish"
    "config/fish/functions/fish_greeting.fish   .config/fish/functions/fish_greeting.fish"
    "config/fonts                               .local/share/fonts/galaga"
)

say() { printf '\e[38;2;215;25;33m●\e[0m %s\n' "$*"; }

# ---- pickers ------------------------------------------------------------------
# Pure-bash lists for the guided questions -- no gum/whiptail/fzf to depend on.
# Up/down (or j/k) move, Space ticks (pick_multi) or selects (pick_one), Enter
# confirms. Keys come from /dev/tty, where the typed prompts read too; without a
# usable terminal (a pipe, CI, TERM=dumb) picker_tty says no and the callers keep
# their typed prompts, unchanged. The choice lands in PICK_OUT (an array for
# pick_multi, one value for pick_one); the terminal is left as it was found, and
# Ctrl-C restores it and stops the run before anything has been installed.

picker_tty() { # a terminal we can draw a list on and read single keys from
    [ -n "${TERM:-}" ] && [ "$TERM" != dumb ] || return 1
    (: </dev/tty) 2>/dev/null && (: >/dev/tty) 2>/dev/null && stty -g </dev/tty >/dev/null 2>&1
}

_pick_stty="" _pick_cols=80 _pick_lines=0 _pick_cur=0 _pick_multi=0 _pick_title=""
_pick_vals=() _pick_labs=()
declare -A _pick_on=()

_pick_open() {
    exec 3<>/dev/tty
    _pick_stty=$(stty -g <&3)
    _pick_cols=$(stty size <&3 2>/dev/null | cut -d' ' -f2)
    case "$_pick_cols" in '' | *[!0-9]*) _pick_cols=80 ;; esac # a terminal that claims
    [ "$_pick_cols" -ge 20 ] || _pick_cols=80 # no width gets the benefit of the doubt
    printf '\e[?25l' >&3 # the cursor would only wander through the list
    stty -echo -icanon min 1 time 0 <&3
    trap '_pick_abort 130' INT
    trap '_pick_abort 143' TERM
}

_pick_close() {
    trap - INT TERM
    [ -n "$_pick_stty" ] && stty "$_pick_stty" <&3 2>/dev/null
    printf '\e[?25h' >&3
    exec 3>&- 3<&-
    _pick_stty=""
}

_pick_abort() { # Ctrl-C: the terminal back first, then stop -- nothing has run yet
    [ -n "$_pick_stty" ] && stty "$_pick_stty" <&3 2>/dev/null
    printf '\e[?25h\n' >&3
    exec 3>&- 3<&-
    exit "$1"
}

_pick_key() { # one keypress -> up/down/space/enter/abort in KEY (anything else: none)
    KEY=none
    local k b
    IFS= read -rn1 k <&3 || { KEY=abort; return; }
    case "$k" in
        $'\e')
            IFS= read -rn1 -t 0.1 b <&3 || { KEY=abort; return; }
            case "$b" in
                '[' | 'O')
                    IFS= read -rn1 -t 0.1 b <&3 || { KEY=abort; return; }
                    case "$b" in A) KEY=up ;; B) KEY=down ;; esac ;;
                *) KEY=abort ;; # a bare Esc cancels, like Ctrl-C
            esac ;;
        ' ') KEY=space ;;
        k) KEY=up ;;
        j) KEY=down ;;
        $'\r' | $'\n' | '') KEY=enter ;;
        $'\003') KEY=abort ;;
    esac
}

_pick_row() { # one frame line: cleared, cut to the terminal's width, counted
    local t=$1
    [ "${#t}" -gt $((_pick_cols - 1)) ] && t="${t:0:$((_pick_cols - 4))}..."
    case "${2:-}" in
        bold) printf '\r\e[K\e[1m%s\e[0m\n' "$t" >&3 ;;
        dim) printf '\r\e[K\e[2m%s\e[0m\n' "$t" >&3 ;;
        *) printf '\r\e[K%s\n' "$t" >&3 ;;
    esac
    _pick_lines=$((_pick_lines + 1))
}

_pick_draw() { # the whole frame, in place: title, one line per option, the keys
    local i mark box
    [ "$_pick_lines" -gt 0 ] && printf '\e[%dA' "$_pick_lines" >&3
    _pick_lines=0
    _pick_row "  $_pick_title"
    for ((i = 0; i < ${#_pick_vals[@]}; i++)); do
        mark='  '; [ "$i" -eq "$_pick_cur" ] && mark='● '
        box=''
        if [ "$_pick_multi" = 1 ]; then
            box='[ ] '; [ -n "${_pick_on[${_pick_vals[$i]}]+x}" ] && box='[✓] '
        fi
        if [ "$i" -eq "$_pick_cur" ]; then _pick_row "$mark$box${_pick_labs[$i]}" bold
        else _pick_row "$mark$box${_pick_labs[$i]}"; fi
    done
    if [ "$_pick_multi" = 1 ]; then _pick_row '  ↑↓ move · space tick · enter done' dim
    else _pick_row '  ↑↓ move · enter picks' dim; fi
}

_pick_finish() { # wipe the frame, leave one summary line where it stood
    local total=$_pick_lines left=$_pick_lines
    printf '\e[%dA' "$total" >&3
    _pick_row "  $1"
    while [ "$left" -gt 1 ]; do printf '\r\e[K\n' >&3; left=$((left - 1)); done
    printf '\e[%dA' "$((total - 1))" >&3
    _pick_lines=0
}

pick_multi() { # $1 title, $2 pre-ticked values (space-separated, "" -- none), rest: value|label
    local title=$1 pre=$2 item v i s=""
    shift 2
    _pick_vals=(); _pick_labs=(); _pick_on=()
    for item in "$@"; do _pick_vals+=("${item%%|*}"); _pick_labs+=("${item#*|}"); done
    for v in $pre; do _pick_on[$v]=1; done
    _pick_title=$title _pick_multi=1 _pick_cur=0 _pick_lines=0
    _pick_open
    while :; do
        _pick_draw
        _pick_key
        case "$KEY" in
            up) _pick_cur=$(((_pick_cur + ${#_pick_vals[@]} - 1) % ${#_pick_vals[@]})) ;;
            down) _pick_cur=$(((_pick_cur + 1) % ${#_pick_vals[@]})) ;;
            space)
                v=${_pick_vals[$_pick_cur]}
                if [ -n "${_pick_on[$v]+x}" ]; then unset '_pick_on[$v]'; else _pick_on[$v]=1; fi ;;
            enter) break ;;
            abort) _pick_abort 130 ;;
        esac
    done
    PICK_OUT=()
    for ((i = 0; i < ${#_pick_vals[@]}; i++)); do
        v=${_pick_vals[$i]}
        [ -n "${_pick_on[$v]+x}" ] || continue
        PICK_OUT+=("$v"); s+="${s:+, }$v"
    done
    [ -n "$s" ] || s=nothing
    _pick_finish "$title: $s"
    _pick_close
}

pick_one() { # $1 title, $2 the value highlighted first, rest: value|label -> PICK_OUT
    local title=$1 start=$2 item i
    shift 2
    _pick_vals=(); _pick_labs=()
    for item in "$@"; do _pick_vals+=("${item%%|*}"); _pick_labs+=("${item#*|}"); done
    _pick_title=$title _pick_multi=0 _pick_cur=0 _pick_lines=0
    for ((i = 0; i < ${#_pick_vals[@]}; i++)); do
        [ "${_pick_vals[$i]}" = "$start" ] && _pick_cur=$i
    done
    _pick_open
    while :; do
        _pick_draw
        _pick_key
        case "$KEY" in
            up) _pick_cur=$(((_pick_cur + ${#_pick_vals[@]} - 1) % ${#_pick_vals[@]})) ;;
            down) _pick_cur=$(((_pick_cur + 1) % ${#_pick_vals[@]})) ;;
            space | enter) break ;;
            abort) _pick_abort 130 ;;
        esac
    done
    PICK_OUT=${_pick_vals[$_pick_cur]}
    _pick_finish "$title: ${_pick_labs[$_pick_cur]}"
    _pick_close
}

extras() { # --with or a prompt -> into EXT, installs yay (and repo packages) separately from AUR
    local w; EXT=()
    [ "$DRY" = 1 ] && WITH="" # a dry run answers everything with the defaults
    if [ -z "${WITH+x}" ]; then
        if picker_tty; then # ticked, not typed; the default is nothing ticked, as Enter was
            local items=() order=(telegram spotify clash pywalfox warp overskride)
            for w in "${order[@]}"; do
                [ -n "${EXTRA[$w]-}" ] && items+=("$w|$w -- ${EXTRA[$w]}")
            done
            pick_multi "what else to install?" "" "${items[@]}"
            WITH="${PICK_OUT[*]}"
        else
            say "what else to install? space-separated, Enter -- nothing"
            for w in "${!EXTRA[@]}"; do printf '  %-9s %s\n' "$w" "${EXTRA[$w]}"; done
            read -rp "  > " WITH || true
        fi
    fi
    for w in ${WITH//,/ }; do
        [ -n "${EXTRA[$w]-}" ] || { echo "no such option: $w (available: ${!EXTRA[*]})"; exit 1; }
        EXT+=(${EXTRA[$w]})
    done
}

browsers() { # a prompt or --browsers -> browser packages into EXT, the first pick into BPICK
    local w; BPICK=""
    [ "$DRY" = 1 ] && BWITH="firefox" # a dry run answers with the default, like extras
    if [ -z "${BWITH+x}" ]; then
        if [ -n "${WITH+x}" ] || ! { : </dev/tty; } 2>/dev/null; then
            BWITH="firefox" # a scripted run (--with, a pipe): the default, as ask_setup does
        elif picker_tty; then # ticked; firefox is pre-ticked -- untick everything for no browser
            local items=() order=(firefox zen chromium brave vivaldi)
            for w in "${order[@]}"; do items+=("$w|$w -- ${BROWSER[$w]}"); done
            pick_multi "which browsers to install?" "firefox" "${items[@]}"
            BWITH="${PICK_OUT[*]}"
        else
            say "which browsers to install? space-separated, Enter -- firefox (none -- no browser)"
            for w in "${!BROWSER[@]}"; do printf '  %-9s %s\n' "$w" "${BROWSER[$w]}"; done
            read -rp "  > " BWITH || true
            case "$BWITH" in "") BWITH="firefox" ;; none) BWITH="" ;; esac
        fi
    fi
    for w in ${BWITH//,/ }; do
        [ -n "${BROWSER[$w]-}" ] || { echo "no such browser: $w (available: ${!BROWSER[*]})"; exit 1; }
        EXT+=(${BROWSER[$w]})
        if [ -z "$BPICK" ]; then BPICK=${BROWSER_CMD[$w]}; fi # an if, not &&: the loop is the
        # function's last word, and a short-circuited && would hand set -e a 1 to kill the flow with
    done
}

browser_bind() { # the Super+W browser follows the first browser picked: one marked line in
    # ~/.config/hypr/user.lua (the override file variables.lua itself points at; keybinds read
    # vars on press, so no relog of the config tree is needed). A browser line of the user's
    # own (no marker) is respected and left alone; no pick -- our line comes back out.
    local f="$HOME/.config/hypr/user.lua"
    say "browser keybind (Super+W)"
    if [ "$DRY" = 1 ]; then
        if [ -n "$BPICK" ]; then note "would set the Super+W browser to $BPICK in user.lua"
        else note "would drop the installer's browser line from user.lua, if it's there"; fi
        return 0
    fi
    BPICK="$BPICK" python3 - "$f" <<'PY'
import os, sys
path, pick = sys.argv[1], os.environ.get("BPICK", "")
MARK = "-- galaga: browser (install.sh)"
lines = []
if os.path.exists(path):
    lines = open(path).read().splitlines()
own = [l for l in lines if 'require("variables").browser' in l and MARK not in l]
if own:
    print("  user.lua sets its own browser -- leaving it")
    sys.exit(0)
lines = [l for l in lines if MARK not in l]
if pick:
    lines.append(f'require("variables").browser = "{pick}" {MARK}')
    print(f"  Super+W opens {pick}")
elif os.path.exists(path):
    print("  no browser picked -- the keybind falls back to variables.lua")
os.makedirs(os.path.dirname(path), exist_ok=True)
open(path, "w").write("\n".join(lines) + ("\n" if lines else ""))
PY
}

packages() {
    say "pacman"
    # pulseaudio modules require pulseaudio itself -- pacman would not let us replace it with pipewire-pulse.
    # As a list, not grep '^pulseaudio-': pulseaudio-alsa and pulseaudio-qt live fine with pipewire
    local pa; pa=$(pacman -Qq pulseaudio-{bluetooth,jack,lirc,rtp,zeroconf,equalizer,equalizer-ladspa} 2>/dev/null || true)
    [ -z "$pa" ] || run sudo pacman -R $pa
    pacman -Q pulseaudio &>/dev/null && say "pacman will ask \"Remove pulseaudio?\" -- answer y, pipewire-pulse replaces it"
    # no --noconfirm: on a conflict (pulseaudio -> pipewire-pulse) it would answer "no" and fail the install
    run sudo pacman -Syu --needed "${PACMAN[@]}"

    if ! command -v yay >/dev/null; then
        say "yay"
        if [ "$DRY" = 1 ]; then
            note "would clone yay-bin and build it (makepkg -si)"
        else
            local tmp; tmp="$(mktemp -d)"
            git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
            (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
            rm -rf "$tmp"
        fi
    fi

    say "aur"
    # AUR is optional: if a package fails, we still install services and links
    run yay -S --needed --noconfirm "${AUR[@]}" || say "aur: not everything installed, see above"
    # separately: if spicetify failed to build, the AUR core is unaffected
    [ ${#EXT[@]} -eq 0 ] || run yay -S --needed --noconfirm "${EXT[@]}" || say "optional: not everything installed, see above"
}

plugins() { # hyprbars -- the window title bars (config/hypr/hyprland/titlebars.lua), built by hyprpm
    say "plugins (hyprpm)"
    if ! command -v hyprpm >/dev/null; then
        # hyprpm used to ship inside the hyprland package; it is a package of its own now,
        # and a system installed before the split (or without it) has no hyprpm at all
        say "hyprpm missing -- installing the hyprpm package"
        run sudo pacman -S --needed hyprpm || true
    fi
    if ! command -v hyprpm >/dev/null; then
        # loud on purpose: without hyprpm there are no title bars, and a silent skip here
        # is exactly how a first login ends up with "unknown config key plugin.hyprbars.*"
        say "WARNING: hyprpm is still not available -- window title bars will NOT work"
        say "fix: sudo pacman -S hyprpm, then hyprpm add https://github.com/hyprwm/hyprland-plugins && hyprpm enable hyprbars"
        return 0
    fi
    # add errors out when the repo is already there -- that is what a re-run looks like
    run hyprpm add https://github.com/hyprwm/hyprland-plugins 2>/dev/null || true
    # no session is running during install: enable only records it, execs.lua loads it at login
    if [ "$DRY" = 1 ]; then run hyprpm enable hyprbars
    elif hyprpm enable hyprbars; then
        say "hyprbars enabled -- window title bars are on from the next login"
    else
        say "hyprpm: hyprbars could not be enabled -- no title bars"
    fi
    say "after every Hyprland upgrade the plugin goes stale: hyprpm update (then hyprpm reload or relog)"
}

bt_policy() { # bluez: the policy set this hardware's audio devices need
    # Four keys in /etc/bluetooth/main.conf, each earned the hard way
    # (earbuds and a speaker that connected, then dropped a breath later,
    # 2026-11-11; the set below is what ended it):
    #   [Policy]  AutoEnable=true      -- the adapter powers on with the daemon,
    #                                     not at the mercy of whichever client asks first
    #   [General] ControllerMode=bredr -- BR/EDR only: the Intel adapter's dual-mode
    #                                     LE path is what these audio devices died on.
    #                                     COST: BLE-only peripherals stop working;
    #                                     set this back to "dual" if you ever get one
    #   [General] Privacy=off          -- LE privacy (rotating addresses) broke
    #                                     reconnections; moot under bredr, set anyway
    #   [General] FastConnectable=false -- the fast page mode's short timeout lost
    #                                     reconnections the normal timing holds
    # main.conf has no drop-in directory, so the distro file is edited in
    # place: each key is set inside its own section only, backup beside it
    local conf=/etc/bluetooth/main.conf
    [ -f "$conf" ] || { note "no $conf -- bluetooth policy skipped"; return 0; }
    if grep -Eq '^[[:space:]]*AutoEnable[[:space:]]*=[[:space:]]*true' "$conf" \
        && grep -Eq '^[[:space:]]*ControllerMode[[:space:]]*=[[:space:]]*bredr' "$conf" \
        && grep -Eq '^[[:space:]]*Privacy[[:space:]]*=[[:space:]]*off' "$conf" \
        && grep -Eq '^[[:space:]]*FastConnectable[[:space:]]*=[[:space:]]*false' "$conf"; then return 0; fi
    if [ "$DRY" = 1 ]; then note "would set the bluetooth policy (AutoEnable, bredr, Privacy off, FastConnectable false) in $conf"; return 0; fi
    sudo cp -n "$conf" "$conf.galaga-backup" || true
    sudo python3 - "$conf" <<'PYEOF'
import sys
path = sys.argv[1]
want = {("Policy", "AutoEnable"): "true",
        ("General", "FastConnectable"): "false",
        ("General", "ControllerMode"): "bredr",
        ("General", "Privacy"): "off"}
lines = open(path).read().splitlines()
out, section, done = [], None, set()
def flush(sec):
    for (s, k), v in want.items():
        if s == sec and (s, k) not in done:
            out.append(k + "=" + v); done.add((s, k))
for line in lines:
    s = line.strip()
    if s.startswith("[") and s.endswith("]"):
        if section is not None: flush(section)
        section = s[1:-1]
        out.append(line)
        continue
    bare = s[1:] if s.startswith("#") else s
    matched = False
    if section is not None and "=" in bare:
        k = bare.split("=", 1)[0].strip()
        if (section, k) in want:
            out.append(k + "=" + want[(section, k)])
            done.add((section, k))
            matched = True
    if not matched: out.append(line)
if section is not None: flush(section)
for sec in ("General", "Policy"):
    if not any((sec, k) in done for (s, k) in want if s == sec):
        out += ["", "[" + sec + "]"]
        flush(sec)
open(path, "w").write("\n".join(out) + "\n")
PYEOF
    run sudo systemctl restart bluetooth
    note "bluetooth: policy set in $conf (backup: $conf.galaga-backup) -- AutoEnable, BR/EDR only, Privacy off, FastConnectable off"
}

warp_quiet() { # the tray applet is started once by the rice (execs.lua). The package also
    # ships a systemd user service for it whose Restart brings the window back seconds
    # after it is closed, and an xdg autostart entry that becomes a second service --
    # mask and hide both, so a killed client stays dead until the next login.
    # Runs whenever warp-taskbar exists on the machine, not only when warp was ticked
    # in this run's extras picker (the picker defaults to nothing ticked, so a re-run
    # without re-ticking it used to silently skip this).
    command -v warp-taskbar >/dev/null 2>&1 || return 0
    run systemctl --user mask warp-taskbar.service
    run systemctl --user stop warp-taskbar.service
    run mkdir -p "$HOME/.config/autostart"
    if [ "$DRY" = 1 ]; then note "would hide the warp xdg autostart entry"
    else printf '[Desktop Entry]\nHidden=true\n' > "$HOME/.config/autostart/com.cloudflare.WarpTaskbar.desktop"; fi
}

services() {
    say "services"
    run sudo systemctl enable NetworkManager bluetooth
    bt_policy
    # the shell's power modes (quick, the bar, settings -> battery) set power-profiles-daemon's profile.
    # tuned and tlp manage the same knobs their own way -- two of them at once fight over the cpu,
    # so if one is already this system's choice, leave it in charge and say what switching takes
    if systemctl is-enabled -q tuned.service 2>/dev/null || systemctl is-enabled -q tlp.service 2>/dev/null \
        || systemctl is-active -q tuned.service 2>/dev/null || systemctl is-active -q tlp.service 2>/dev/null; then
        note "tuned or tlp already manages power here -- power-profiles-daemon is NOT enabled, they would fight"
        note "for the shell's cpu profiles instead: sudo systemctl disable --now tuned tlp; sudo systemctl enable --now power-profiles-daemon"
    else
        run sudo systemctl enable power-profiles-daemon
    fi
    systemctl is-enabled -q display-manager.service 2>/dev/null || run sudo systemctl enable sddm
    # Cloudflare WARP (the warp extra): warp-cli and the tray applet are front-ends for the
    # warp-svc daemon -- enable and start it, or the client has nothing to talk to
    [[ " ${WITH//,/ } " == *" warp "* ]] && run sudo systemctl enable --now warp-svc
    warp_quiet # unconditionally: gated on warp-taskbar existing, not on this run's picks
    run systemctl --user enable pipewire-pulse.socket wireplumber ydotool
    run sudo usermod -aG input,video "$USER" # ydotool (uinput), brightnessctl
    run xdg-user-dirs-update
}

links() {
    say "symlinks (old -> $BACKUP)"
    local src dst
    for l in "${LINKS[@]}"; do
        read -r src dst <<<"$l"
        src="$DOTS/$src" dst="$HOME/$dst"
        [ "$(readlink "$dst")" = "$src" ] && continue
        if [ "$DRY" = 1 ]; then
            if [ -e "$dst" ] || [ -L "$dst" ]; then note "would move $dst to the backup and link $src there"
            else note "would link $dst -> $src"; fi
            continue
        fi
        if [ -e "$dst" ] || [ -L "$dst" ]; then
            mkdir -p "$BACKUP/$(dirname "${dst#"$HOME"/}")"
            mv "$dst" "$BACKUP/${dst#"$HOME"/}"
        fi
        mkdir -p "$(dirname "$dst")"
        ln -s "$src" "$dst"
        echo "  $dst"
    done
    # rules.json and kitty.conf are created by the shell itself; rice starts galaga and builds the folder theme
    if [ "$DRY" = 1 ]; then
        note "would write galaga to ${XDG_STATE_HOME:-$HOME/.local/state}/rice/shell, seed the starter wallpapers and LocalSend's dark start"
    else
        mkdir -p "$HOME/.config/demonshot" "${XDG_STATE_HOME:-$HOME/.local/state}/rice"
        echo galaga > "${XDG_STATE_HOME:-$HOME/.local/state}/rice/shell"
        mkdir -p "$HOME/Pictures/Wallpapers" # wallpaper picker (Super+Shift+W) looks here
        # the five starter wallpapers (assets/wallpapers, CC0 -- generated for the rice): copied, never
        # overwriting -- once they're yours they're yours (AMM021's installer does the same)
        local w
        for w in "$DOTS"/assets/wallpapers/*.jpg; do [ -e "$HOME/Pictures/Wallpapers/$(basename "$w")" ] || cp "$w" "$HOME/Pictures/Wallpapers/"; done
        # LocalSend starts dark on OLED black (its accent follows the GTK one); only before its first
        # run -- after that its settings are the user's
        local ls="$HOME/.local/share/org.localsend.localsend_app/shared_preferences.json"
        [ -e "$ls" ] || { mkdir -p "${ls%/*}"; echo '{"flutter.ls_theme":"dark","flutter.ls_color":"oled"}' > "$ls"; }
    fi
    run fc-cache -f
    command -v gsettings >/dev/null || return 0 # --links on a system without GNOME schemas
    # dark mode for Zen, Electron and libadwaita (through the portal) and a dark gtk3 base for our gtk.css
    run gsettings set org.gnome.desktop.interface color-scheme prefer-dark
    run gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark
    # window buttons for apps that read it from here (the rest read settings.ini):
    # close and maximise, on the left -- maximise works for these apps (rules.lua
    # exempts them from the maximise suppression); minimise is not rendered
    # because its click cannot work on Hyprland (see term/gtk-3.0/settings.ini)
    run gsettings set org.gnome.desktop.wm.preferences button-layout 'close,maximize:appmenu'
}

browser_cleanup() { # firefox/zen: take OUT the inTitlebar user.js snippet older installs deployed.
    # Browsers are own-buttons apps now (rules.lua): they keep their built-in buttons, so the
    # pref must not be set anywhere -- a profile that kept it would draw no buttons of its own
    # AND get no hyprbar: a buttonless window. This removes exactly what the old step shipped:
    # the whole user.js where it consists of the snippet alone, and just the snippet where it
    # was appended to the user's own file (the rest stays byte-identical). Safe to re-run:
    # a profile without the snippet is left untouched.
    say "browser cleanup (firefox/zen user.js)"
    if [ "$DRY" = 1 ]; then note "would remove the old inTitlebar snippet from firefox/zen profiles, if it's there"; return 0; fi
    local marker='// galaga -- window buttons (see README: "Window buttons")'
    local pref='user_pref("browser.tabs.inTitlebar", 0);'
    # everywhere firefox/zen keep profiles: the native homes, and the flatpak homes --
    # a flatpak's profile store sits under ~/.var/app/<app id>/, invisible to a plain
    # ~/.mozilla glob (a flatpak firefox is the common CachyOS install). Zen's flatpak
    # id is app.zen_browser.zen (io.github.zen_browser.zen before 1.6); its tarball
    # builds profile under ~/.config/zen instead of ~/.zen.
    local bases=(
        "$HOME/.mozilla/firefox"
        "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox"
        "$HOME/.zen"
        "$HOME/.config/zen"
        "$HOME/.var/app/app.zen_browser.zen/.zen"
        "$HOME/.var/app/io.github.zen_browser.zen/.zen"
    )
    # collect the profile dirs: the usual *.default* names (zen spells it *.Default*),
    # plus whatever profiles.ini registers -- a profile can live under any name there
    local dirs=() base d p
    for base in "${bases[@]}"; do
        [ -d "$base" ] || continue # layout not present on this machine -- nothing to do
        for d in "$base"/*.default*/ "$base"/*.Default*/; do
            [ -d "$d" ] && dirs+=("${d%/}")
        done
        if [ -f "$base/profiles.ini" ]; then
            while IFS= read -r p; do
                case "$p" in /*) d="$p" ;; *) d="$base/$p" ;; esac
                [ -d "$d" ] && dirs+=("$d")
            done < <(awk -F= '$1 == "Path" || $1 == "Default" { sub(/^[^=]*=/, ""); print }' "$base/profiles.ini" || true)
        fi
    done
    local uniq=() seen target cleaned=0 removed=0 clean=0 tmp
    for d in "${dirs[@]}"; do
        # the same dir can arrive via a glob and via profiles.ini -- clean it once
        seen=0
        for p in "${uniq[@]}"; do [ "$p" = "$d" ] && { seen=1; break; }; done
        [ "$seen" -eq 0 ] && uniq+=("$d")
    done
    for d in "${uniq[@]}"; do
        target="$d/user.js"
        [ -f "$target" ] || continue
        if ! grep -qF "$pref" "$target" && ! grep -qF "$marker" "$target"; then
            clean=$((clean + 1)) # nothing of ours in there -- leave the file exactly as it is
            continue
        fi
        # a copy goes to the backup before the file is touched, like every other edit here
        mkdir -p "$BACKUP/$(dirname "${target#"$HOME"/}")"
        cp "$target" "$BACKUP/${target#"$HOME"/}"
        tmp="$(mktemp)"
        # drop our block (the marker line, its comment lines, the pref line, and the blank
        # line the old step put in front of the block) plus any lone pref line; keep the rest
        awk -v marker="$marker" -v pref="$pref" '
            $0 == marker { inblock = 1; if (n > 0 && buf[n] == "") n--; next }
            inblock && $0 == pref { inblock = 0; next }
            inblock && /^\/\// { next }
            inblock { inblock = 0 }
            $0 == pref { next }
            { buf[++n] = $0 }
            END { for (i = 1; i <= n; i++) print buf[i] }
        ' "$target" >"$tmp"
        if [ -s "$tmp" ]; then
            cat "$tmp" >"$target" # in place: same file, its permissions survive
            cleaned=$((cleaned + 1))
            echo "  $target (snippet removed)"
        else
            rm "$target" # the file was the snippet alone
            removed=$((removed + 1))
            echo "  $target (was only the snippet -- deleted)"
        fi
        rm -f "$tmp"
    done
    if [ ${#uniq[@]} -eq 0 ]; then
        say "browser cleanup: no firefox/zen profiles found -- nothing to remove"
    elif [ $((cleaned + removed)) -eq 0 ]; then
        say "browser cleanup: $clean profile(s) already clean"
    else
        say "browser cleanup: $cleaned cleaned, $removed removed, $clean already clean -- restart the browser"
    fi
}

tmux_theme() { # tmux follows the palette: Theme.apps() writes ~/.config/tmux/theme.conf, but it only
    # colours anything if tmux.conf sources it -- add that line to an existing config (either home).
    # No tmux, or no config, or the line already there: nothing to do (AMM021's installer does the same)
    command -v tmux >/dev/null || return 0
    if [ "$DRY" = 1 ]; then note "would add the theme.conf source line to your tmux.conf, if it isn't there"; return 0; fi
    local conf
    for conf in "$HOME/.config/tmux/tmux.conf" "$HOME/.tmux.conf"; do
        [ -f "$conf" ] || continue
        grep -qs 'tmux/theme.conf' "$conf" && return 0
        echo 'source-file -q ~/.config/tmux/theme.conf # galaga: colors written by the shell' >> "$conf"
        echo "  $conf (+ theme.conf source)"
        return 0
    done
}

flatpak_gtk() { # flatpak apps are sandboxed off from ~/.config/gtk-* -- grant the installed ones read access,
    # or their headerbar buttons never see the gtk.css discs (GNOME Calculator is usually a flatpak).
    # Read-only and per-app; the button-layout the apps already show comes from gsettings, which does reach them.
    command -v flatpak >/dev/null || return 0
    if [ "$DRY" = 1 ]; then note "would grant the installed GNOME flatpaks read access to the gtk config"; return 0; fi
    say "flatpak gtk access"
    local apps=(org.gnome.Calculator org.gnome.Nautilus org.gnome.TextEditor org.gnome.Loupe org.gnome.Papers
                org.gnome.Calendar org.gnome.Clocks org.gnome.Contacts org.gnome.Weather org.gnome.Characters)
    local installed app
    installed="$(flatpak list --app --columns=application 2>/dev/null || true)"
    for app in "${apps[@]}"; do
        grep -qx "$app" <<<"$installed" || continue # not installed as a flatpak -- nothing to grant
        # already granted (by us or by hand): a re-run changes nothing
        flatpak override --user --show "$app" 2>/dev/null | grep -q 'gtk-4.0' && continue
        if flatpak override --user "$app" --filesystem=xdg-config/gtk-3.0:ro --filesystem=xdg-config/gtk-4.0:ro; then
            echo "  $app"
        else
            say "flatpak: could not grant gtk config access to $app"
        fi
    done
}

LOGIN="" FILES="" BOOT=""
ask_setup() { # every question first (AMM021's flow): the file manager, the login screen
    # and the boot screen are asked here, the extras in extras() -- after that, one
    # password and no more questions.
    # Only at a terminal and only without --with: scripts and pipes get the defaults.
    [ -z "${WITH+x}" ] && { : </dev/tty; } 2>/dev/null || return 0
    say "a few choices (Enter keeps the default)"
    local a
    if picker_tty; then # picked from a list; thunar is the default, as Enter was
        pick_one "file manager" thunar "thunar|thunar" "dolphin|dolphin"
        FILES=$PICK_OUT
    else
        printf '  file manager [thunar] / dolphin: '
        read -r a </dev/tty || a=""
        case "$a" in dolphin) FILES=dolphin ;; *) FILES=thunar ;; esac
    fi
    if picker_tty; then # picked from a list; "keep" is the default, as Enter was
        pick_one "login screen" keep \
            "keep|keep -- your current login screen" \
            "greeter|galaga -- the galaga face (greetd)"
        case "$PICK_OUT" in keep) LOGIN="" ;; *) LOGIN=$PICK_OUT ;; esac
    else
        printf '  login screen [keep] / galaga: '
        read -r a </dev/tty || a=""
        case "$a" in galaga) LOGIN=greeter ;; *) LOGIN="" ;; esac
    fi
    # the boot screen: quiet is the splash with no text, verbose is the boot
    # logs on the console. The starting answer is the state the machine is
    # already in (qb_boot_default, in the quiet-boot block below), so pressing
    # Enter through a re-run flips nothing; install_flow applies the pick at
    # the end through quiet_boot itself, the --quiet-boot modes' own path
    BOOT=$(qb_boot_default)
    if picker_tty; then # picked from a list, like the questions above
        pick_one "boot screen" "$BOOT" \
            "quiet|quiet -- the splash, no boot text" \
            "verbose|verbose -- show the boot logs"
        BOOT=$PICK_OUT
    else
        local other=verbose; [ "$BOOT" = verbose ] && other=quiet
        printf '  boot screen [%s] / %s: ' "$BOOT" "$other"
        read -r a </dev/tty || a=""
        case "$a" in quiet | verbose) BOOT=$a ;; esac
    fi
}

KEEPER=""
sudo_once() { # one password, then sudo stays alive so nothing stops to ask again
    [ "$DRY" = 1 ] && return 0
    if sudo -n true 2>/dev/null; then :; else
        say "your password, once"
        sudo -v
    fi
    ( trap - ERR; set +e; while kill -0 $$ 2>/dev/null; do sudo -n true; sleep 50; done ) >/dev/null 2>&1 &
    KEEPER=$!
    trap '[ -z "$KEEPER" ] || kill "$KEEPER" 2>/dev/null || true' EXIT
}

set_file_manager() { # the guided choice, applied (AMM021's set_file_manager): the xdg default,
    # and for Dolphin the pieces Plasma would normally provide
    command -v xdg-mime >/dev/null || return 0
    case "$FILES" in
        dolphin)
            run xdg-mime default org.kde.dolphin.desktop inode/directory
            # outside Plasma nothing provides the menu KDE apps read their app list from, and
            # "Open With" comes up empty. Yours is left alone if you have one
            local menu="$HOME/.config/menus/applications.menu"
            if [ ! -e "$menu" ] && [ -r /etc/xdg/menus/arch-applications.menu ]; then
                run mkdir -p "${menu%/*}"
                run cp -n /etc/xdg/menus/arch-applications.menu "$menu" || true
            fi
            # "Open Terminal" and the F4 panel use this; a choice you already made stays
            if [ -z "$(kreadconfig6 --file kdeglobals --group General --key TerminalApplication 2>/dev/null)" ]; then
                run kwriteconfig6 --file kdeglobals --group General --key TerminalApplication kitty || true
            fi
            run kbuildsycoca6 --noincremental || true
            note "Super+E still follows variables.lua (fileExplorer) -- set it to dolphin there if you want the key to match"
            ;;
        *) run xdg-mime default thunar.desktop inode/directory ;;
    esac
}

pacman_hook() { # after a system update, pacman says if the rice has news. It runs as you, never
    # as root: the script lives in your home, and root shouldn't execute that (AMM021's hook)
    [ -e /etc/pacman.d/hooks/galaga.hook ] && return 0
    run sudo mkdir -p /etc/pacman.d/hooks
    if [ "$DRY" = 1 ]; then note "would add the pacman hook"; return 0; fi
    printf '[Trigger]\nOperation = Upgrade\nType = Package\nTarget = *\n\n[Action]\nDescription = Checking for rice updates...\nWhen = PostTransaction\nExec = /usr/bin/runuser -u %s -- /usr/bin/env HOME=%s /usr/bin/bash %s/config/pacman/rice-notify.sh\n' "$USER" "$HOME" "$DOTS" \
        | sudo tee /etc/pacman.d/hooks/galaga.hook >/dev/null || say "could not add the pacman hook -- ./install.sh --update still works"
}

kernel_note() { # the update replaced the running kernel: its modules are gone, so anything
    # module-shaped (wifi, gpu) breaks until a reboot -- say so instead of looking broken
    [ "$DRY" = 1 ] && return 0
    [ -d "/usr/lib/modules/$(uname -r)" ] || say "note: the running kernel ($(uname -r)) was replaced -- reboot before judging anything broken"
}

update() { # step 1: the new code. Bash reads a script as it runs, so step 2 starts fresh from the new file
    local old; old=$(git -C "$DOTS" rev-parse HEAD)
    say "getting the newest version"
    if ! git -C "$DOTS" pull --ff-only; then
        say "could not update: local changes or no connection, see above. Nothing changed."
        exit 1
    fi
    exec "$DOTS/install.sh" --update-rest "$old"
}

update_rest() { # step 2: whatever the new version needs. Asks for a password only if something needs it
    local old=$1 missing aur_missing
    if [ "$old" = "$(git -C "$DOTS" rev-parse HEAD)" ]; then say "already up to date."; return 0; fi
    git -C "$DOTS" log --format='  · %s' "$old..HEAD" | cut -c1-100
    # pacman -T lists what isn't installed, and needs no password
    missing=$(pacman -T "${PACMAN[@]}" || true)
    aur_missing=$(pacman -T "${AUR[@]}" || true)
    # the greeters run from copies, which only change when their own inputs do
    local greeter_changed="" watch='^config/greetd/|^config/quickshell/galaga/(greet\.qml|lock/|Theme\.qml|components/)'
    local dm=""
    if [ -L /etc/systemd/system/display-manager.service ]; then dm="$(basename "$(readlink -f /etc/systemd/system/display-manager.service)" .service)"; fi
    if [ "$dm" = greetd ] && git -C "$DOTS" diff --name-only "$old" HEAD | grep -qE "$watch"; then greeter_changed=1; fi
    local hook_missing=""
    [ -e /etc/pacman.d/hooks/galaga.hook ] || hook_missing=1
    if [ -n "$missing$aur_missing$greeter_changed$hook_missing" ]; then sudo_once; fi
    [ -n "$hook_missing" ] && pacman_hook
    # shellcheck disable=SC2086 # one package per word
    [ -z "$missing" ] || run sudo pacman -S --needed --noconfirm $missing
    # shellcheck disable=SC2086
    [ -z "$aur_missing" ] || run yay -S --needed --noconfirm $aur_missing || say "aur: not everything installed, see above"
    links
    warp_quiet # --update never ran services(), so the mask was never re-applied either
    [ -z "$greeter_changed" ] || greeter
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then run "$DOTS/config/quickshell/rice/rice" restart; fi
    kernel_note
    say "updated. Your choices and settings are as they were."
}

needs_psk() { # a password network with no password stored
    case "$(nmcli -g 802-11-wireless-security.key-mgmt connection show "$1" 2>/dev/null)" in wpa-psk | sae) ;; *) return 1 ;; esac
    [ -z "$(nmcli -s -g 802-11-wireless-security.psk connection show "$1" 2>/dev/null)" ]
}

# ---- KDE Wallet: Plasma keeps each password in the folder "Network Management" under "{uuid};802-11-wireless-security", as JSON ----
WALLET_KEYS=""
wallet_open() { # one call, so a locked wallet asks once. Empty if there's no wallet, or it stays locked
    command -v kwallet-query >/dev/null || return 0
    say "opening KDE Wallet to read the saved passwords -- it may ask for the wallet's password once"
    WALLET_KEYS=$(timeout 120 kwallet-query -l -f "Network Management" kdewallet 2>/dev/null | grep -F ';802-11-wireless-security' || true)
}
wallet_has() { case "$WALLET_KEYS" in *"{$1};"*) return 0 ;; *) return 1 ;; esac; }
wallet_psk() { # prints the password; nothing if it can't be read
    wallet_has "$1" || return 0
    timeout 30 kwallet-query -r "{$1};802-11-wireless-security" -f "Network Management" kdewallet 2>/dev/null | jq -r '.psk // empty' 2>/dev/null || true
}

fix_plasma() { # coming from KDE Plasma (AMM021's --fix-plasma): things that worked there because
    # Plasma's own helpers were running. The big one is the login-refused root cause: a Wi-Fi
    # password kept in KDE Wallet (psk-flags 1) or asked every time (2) is not there at boot, and
    # a per-user profile cannot connect before login -- under greetd that reads as "login refused".
    say "fixing what Plasma left behind"
    command -v nmcli >/dev/null || { say "no NetworkManager here -- nothing to fix"; return 0; }
    local u t name flags perm why items=() active
    active=$(nmcli -g UUID,ACTIVE connection show 2>/dev/null | awk -F: '$2 == "yes" {print $1}')
    local any_wallet=""
    while IFS=: read -r u t; do
        if [ "$t" = 802-11-wireless ] && [ "$(nmcli -g 802-11-wireless-security.psk-flags connection show "$u" 2>/dev/null)" = 1 ]; then any_wallet=1; fi
    done < <(nmcli -g UUID,TYPE connection show 2>/dev/null)
    [ -z "$any_wallet" ] || wallet_open
    while IFS=: read -r u t; do
        [ "$t" = 802-11-wireless ] || continue
        flags=$(nmcli -g 802-11-wireless-security.psk-flags connection show "$u" 2>/dev/null)
        perm=$(nmcli -g connection.permissions connection show "$u" 2>/dev/null)
        case "$flags" in 1) why="password in KDE Wallet" ;; 2) why="asks every time" ;; *) why="" ;; esac
        if wallet_has "$u"; then why="found in KDE Wallet"; fi
        if [ -z "$why" ] && needs_psk "$u"; then why="no password saved"; fi
        if [ -z "$why" ] && [ -z "$perm" ]; then continue; fi
        name=$(nmcli -g connection.id connection show "$u" 2>/dev/null | tr -d '|' | cut -c1-22)
        items+=("$u|$name|${why:-only connects after login}")
    done < <(nmcli -g UUID,TYPE connection show 2>/dev/null)
    if [ ${#items[@]} -eq 0 ]; then
        say "wi-fi: every saved network has its password and can connect at boot -- KDE Wallet isn't the cause"
    else
        say "wi-fi: ${#items[@]} saved network(s) won't connect by themselves:"
        local it
        for it in "${items[@]}"; do IFS='|' read -r u name why <<<"$it"; note "$name -- $why"; done
        local a
        printf '  migrate them so they connect at boot? [y/N] '
        read -r a </dev/tty || a=""
        case "$a" in y | Y)
            for it in "${items[@]}"; do
                IFS='|' read -r u name why <<<"$it"
                flags=$(nmcli -g 802-11-wireless-security.psk-flags connection show "$u" 2>/dev/null)
                if [ "$flags" = 1 ] || [ "$flags" = 2 ] || needs_psk "$u"; then
                    local p; p=$(wallet_psk "$u")
                    # shorter than any Wi-Fi password: not something usable from the wallet
                    if [ ${#p} -lt 8 ]; then p=""; else note "$name: password from KDE Wallet"; fi
                    while [ -z "$p" ]; do
                        read -rsp "  password for $name (nothing shows; Enter alone skips it): " p </dev/tty; echo
                        [ -z "$p" ] && break
                        [ ${#p} -ge 8 ] && break
                        say "wi-fi passwords have at least 8 characters"
                        p=""
                    done
                    [ -z "$p" ] && { note "skipped $name"; continue; }
                    if nmcli connection modify "$u" 802-11-wireless-security.psk-flags 0 802-11-wireless-security.psk "$p" connection.permissions ""; then say "saved $name"; else say "could not save $name, see above"; fi
                else
                    if nmcli connection modify "$u" connection.permissions ""; then say "$name now connects before login"; else say "could not change $name, see above"; fi
                fi
            done ;;
        *) note "left as they are" ;;
        esac
    fi
    # ---- autostart: Plasma's helpers that make no sense here. Plasma keeps them; this only applies under Hyprland ----
    local f d found=""
    # an earlier version of AMM021's command could leave a junk file here
    find "$HOME/.config/autostart" -maxdepth 1 -type f -name '*●*' -delete 2>/dev/null || true
    while IFS= read -r f; do # line by line, not word-split: an entry's name can hold a space
        d=$HOME/.config/autostart/${f##*/}
        found=1
        if grep -qs 'NotShowIn=.*Hyprland' "$d" 2>/dev/null; then note "xwaylandvideobridge is already stopped under Hyprland"; continue; fi
        mkdir -p "$HOME/.config/autostart"
        local body; body=$(grep -v '^NotShowIn=' "$f")
        printf '%s\nNotShowIn=Hyprland;\n' "$body" > "$d"
        say "stopped xwaylandvideobridge under Hyprland. To undo: delete $d"
    done < <(grep -ls 'xwaylandvideobridge' /etc/xdg/autostart/*.desktop "$HOME"/.config/autostart/*.desktop 2>/dev/null || true)
    [ -n "$found" ] || note "xwaylandvideobridge has no autostart entry here, so something else starts it"
    say "done. Reboot to check."
}

uninstall() { # take the links away, put the old files and the old login screen back (AMM021's
    # --uninstall, on this installer's backups). Packages stay installed; settings stay in place
    say "uninstalling"
    { : </dev/tty; } 2>/dev/null || { say "needs a terminal to ask -- run it there"; return 1; }
    local a
    printf '  remove the links and restore your old files and login screen? Packages stay. [y/N] '
    read -r a </dev/tty || a=""
    case "$a" in y | Y) ;; *) say "left as it is"; return 0 ;; esac
    # the oldest backup holds the pre-rice originals
    local first; first=$(find "$HOME" -maxdepth 1 -type d -name '.dots-backup-*' 2>/dev/null | sort | head -n1)
    local state="${XDG_STATE_HOME:-$HOME/.local/state}/rice"
    local l src dst
    for l in "${LINKS[@]}"; do
        read -r src dst <<<"$l"
        src="$DOTS/$src" dst="$HOME/$dst"
        # gtk and qt files may point at the shell's recoloured copies instead of the repo
        case "$(readlink "$dst" 2>/dev/null)" in
            "$src" | "$state"/galaga/*) rm "$dst" ;;
            *) continue ;;
        esac
        if [ -n "$first" ] && { [ -e "$first/${dst#"$HOME"/}" ] || [ -L "$first/${dst#"$HOME"/}" ]; }; then
            mv "$first/${dst#"$HOME"/}" "$dst"
            echo "  restored $dst"
        fi
    done
    # the login screen: the greeter steps recorded the previous DM in their run's backup
    local old="" b
    for b in $(find "$HOME" -maxdepth 1 -type d -name '.dots-backup-*' 2>/dev/null | sort -r); do
        [ -r "$b/previous-display-manager.txt" ] && { old=$(cat "$b/previous-display-manager.txt"); break; }
    done
    local dm=""
    if [ -L /etc/systemd/system/display-manager.service ]; then dm="$(basename "$(readlink -f /etc/systemd/system/display-manager.service)" .service)"; fi
    if [ -n "$old" ] && [ "$old" != "$dm" ]; then
        sudo_once
        [ -z "$dm" ] || sudo systemctl disable "$dm"
        sudo systemctl enable "$old"
        say "login screen back to $old"
    elif [ "$dm" = greetd ] || [ "$dm" = sddm ]; then
        note "$dm stays enabled: no earlier login screen is on record"
    fi
    if [ -e /etc/pacman.d/hooks/galaga.hook ]; then sudo_once; sudo rm /etc/pacman.d/hooks/galaga.hook; fi
    say "done. Packages, your settings in $state and the backups stay in place."
}

install_flow() { # the guided install: questions, one password, then straight through
    ask_setup
    extras
    browsers
    [ "$FILES" = dolphin ] && EXT+=(dolphin kio-extras ffmpegthumbs kdegraphics-thumbnailers archlinux-xdg-menu kde-cli-tools)
    sudo_once
    packages; plugins; services; links; browser_cleanup; browser_bind; flatpak_gtk; tmux_theme; pacman_hook
    [ -n "$FILES" ] && set_file_manager
    case "$LOGIN" in
        greeter) if [ "$DRY" = 1 ]; then note "would run the greeter step (./install.sh --greeter)"; else greeter; fi ;;
    esac
    # the boot screen, applied through the modes' own function -- and after the
    # greeter step, so a greeter config installed by this same run gets its
    # quiet wrap too. No BOOT (a script, a pipe, --with): left exactly as it is
    case "$BOOT" in
        quiet) quiet_boot on ;;
        verbose) quiet_boot off ;;
        *) note "boot screen: left as it is -- no answer was given, and a scripted run never changes the boot (./install.sh --quiet-boot / --no-quiet-boot change it any time)" ;;
    esac
    # spicetify needs Spotify already downloaded and logged in, so there is nothing to apply before the first launch
    [[ " ${WITH//,/ } " == *" spotify "* ]] && say "spotify: launch it, log in, then spicetify config custom_apps marketplace && spicetify backup apply"
    [[ " ${WITH//,/ } " == *" warp "* ]] && say "warp: once -- warp-cli registration new, then warp-cli connect; its icon lives in the tray from the next login"
    kernel_note
    if [ "$DRY" = 1 ]; then say "dry run done -- nothing was changed"; else say "done. reboot and pick Hyprland in sddm"; fi
}

greeter() { # boot login: greetd + the lock's face as the greeter (./install.sh --greeter).
    # Replaces the current display manager -- deliberately NOT part of the default run.
    # Order is the safety story: packages, files and config all land first; the DM swap is
    # the very last step, so a failure anywhere above leaves the old login untouched.
    say "greeter (greetd)"
    sudo pacman -S --needed "${GREETER_PACMAN[@]}"

    # the shell config at a system path: the greeter runs as the "greeter" user and cannot
    # read ~/.config. A copy, not a symlink -- re-run --greeter after a pull to refresh it
    if ! sudo diff -qr "$DOTS/$G" /etc/greetd/galaga >/dev/null 2>&1; then
        sudo rm -rf /etc/greetd/galaga
        sudo mkdir -p /etc/greetd
        sudo cp -r "$DOTS/$G" /etc/greetd/galaga
        echo "  /etc/greetd/galaga"
    fi
    sudo chmod -R go+rX /etc/greetd/galaga # root-owned repo files are group-only: the greeter user needs read+traverse

    # the fonts, system-wide: the greeter user cannot see ~/.local/share/fonts either --
    # without this the Doto clock falls back to a default font and the face is not the face
    if ! diff -qr "$DOTS/config/fonts" /usr/share/fonts/galaga >/dev/null 2>&1; then
        sudo mkdir -p /usr/share/fonts/galaga
        sudo cp "$DOTS/config/fonts"/*.ttf "$DOTS/config/fonts"/*.otf "$DOTS/config/fonts"/OFL.txt /usr/share/fonts/galaga/
        sudo fc-cache -f >/dev/null
        echo "  /usr/share/fonts/galaga"
    fi

    # profile photos for the greeter face: the greeter user cannot read a ~/.face inside a
    # 700 home, so each human user's face gets a world-readable copy of its own (the face
    # itself is not a secret -- AccountsService keeps the same file world-readable too).
    # No ~/.face -- nothing copied for that user, and their face falls back to dots.
    sudo mkdir -p /etc/greetd/faces
    local gu guid ghome
    while IFS=: read -r gu _ guid _ _ ghome _; do
        { [ "$guid" -ge 1000 ] && [ "$guid" -lt 60000 ] && [ -f "$ghome/.face" ]; } 2>/dev/null || continue
        sudo cp "$ghome/.face" "/etc/greetd/faces/$gu"
        sudo chmod 644 "/etc/greetd/faces/$gu"
        echo "  /etc/greetd/faces/$gu"
    done < <(getent passwd)
    # the lock's own wallpaper (settings -> lock keeps a copy in the state dir): the greeter face
    # shows it too, from the one synced copy. The invoking user's copy wins -- the greeter
    # face is one screen, whichever user it lists first
    local lw
    for lw in "${XDG_STATE_HOME:-$HOME/.local/state}/rice"/lockwall.*; do
        [ -f "$lw" ] || continue
        sudo cp "$lw" /etc/greetd/faces/lockwall
        sudo chmod 644 /etc/greetd/faces/lockwall
        echo "  /etc/greetd/faces/lockwall"
        break
    done

    # greetd's own files (config, the stripped compositor config, the launcher script):
    # a changed one that already exists goes to the backup first -- once, only on change
    local f
    for f in config.toml hyprland.lua galaga-greeter; do
        sudo cmp -s "$DOTS/config/greetd/$f" "/etc/greetd/$f" && continue
        if [ -e "/etc/greetd/$f" ]; then
            mkdir -p "$BACKUP/etc/greetd"
            sudo cp "/etc/greetd/$f" "$BACKUP/etc/greetd/$f"
            sudo chown "$USER" "$BACKUP/etc/greetd/$f"
            echo "  old /etc/greetd/$f -> $BACKUP/etc/greetd/$f"
        fi
        sudo mkdir -p /etc/greetd
        sudo cp "$DOTS/config/greetd/$f" "/etc/greetd/$f"
        echo "  /etc/greetd/$f"
    done
    sudo chmod 755 /etc/greetd/galaga-greeter

    # the swap -- only now, with greetd installed and configured. Which DM is on today:
    local old=""
    if [ -L /etc/systemd/system/display-manager.service ]; then
        old="$(basename "$(readlink -f /etc/systemd/system/display-manager.service)" .service)"
    fi
    [ "$old" = greetd ] && old="" # a re-run: greetd already is the display manager
    if [ -n "$old" ]; then
        mkdir -p "$BACKUP"
        echo "$old" > "$BACKUP/previous-display-manager.txt"
        sudo systemctl disable "$old"
        echo "  disabled: $old (recorded in $BACKUP/previous-display-manager.txt)"
    fi
    if systemctl is-enabled -q greetd 2>/dev/null; then
        echo "  greetd already enabled"
    else
        sudo systemctl enable greetd
        echo "  enabled: greetd"
    fi

    say "greeter is the boot login from the next reboot"
    if [ -n "$old" ]; then
        say "rollback: sudo systemctl disable greetd && sudo systemctl enable $old"
        say "  (greetd's config backup, if any, is in $BACKUP/etc/greetd/ -- cp it back to /etc/greetd/)"
    else
        say "rollback: sudo systemctl disable greetd, then enable your old display manager"
    fi
    say "no login screen at boot? Ctrl+Alt+F3 -> log in on the text console -> run the rollback"
}

# ---- quiet boot ------------------------------------------------------------------
# --quiet-boot / --no-quiet-boot: nothing prints on the console on the way to the
# desktop, in three layers:
#   1. the kernel command line gains/loses QB_TOKENS -- quiet + the log levels
#      down, splash up.
#   2. the greeter's launch (our /etc/greetd/config.toml) sends its output to a
#      log file instead of printing on the console.
#   3. the user session: a galaga.desktop beside the uwsm Hyprland entry runs
#      the same command with its output appended to a log in the user's state
#      dir -- that is where the "Selected compositor ID..." / "Created unit..."
#      block after login comes from. The greeter face prefers the quiet entry
#      while it exists (greet.qml), so removing the file is the whole revert
#      for this layer.
#   Three layouts are recognized positively (an entry's options line, a limine
#   kernel_command_line/cmdline line, GRUB_CMDLINE_LINUX_DEFAULT): only those
#   lines are ever edited, several layouts can coexist and each is edited (the
#   tokens are harmless in one that never boots), and anything unrecognized is
#   left exactly as it is -- a guessed edit here bricks boots. Unified kernel
#   images carry the line inside the image: recognized, reported, untouchable.
#   Every edited file is backed up once at <file>.galaga-bak before it moves.
# Plymouth is only reported on: the splash shows only if plymouth is installed
# AND in the mkinitcpio HOOKS; neither is installed or re-hooked from here.
# The guided flow asks the same choice as its boot-screen question and applies
# the answer through quiet_boot itself; qb_detect_state / qb_boot_default
# below are what the question reads to start from the machine's own state.
# The QB_* paths are the real ones; the fixture tests point them at a scratch tree.
QB_TOKENS=(quiet splash loglevel=3 systemd.show_status=auto rd.systemd.show_status=auto rd.udev.log_level=3)
QB_BOOT_DIR=${QB_BOOT_DIR:-/boot}
QB_LIMINE_EFI=${QB_LIMINE_EFI:-/boot/EFI/limine/limine.conf}
QB_GRUB_CONF=${QB_GRUB_CONF:-/etc/default/grub}
QB_GRUB_CFG=${QB_GRUB_CFG:-/boot/grub/grub.cfg}
QB_MKINITCPIO=${QB_MKINITCPIO:-/etc/mkinitcpio.conf}
QB_GREETD_CONF=${QB_GREETD_CONF:-/etc/greetd/config.toml}
QB_SESSIONS_DIR=${QB_SESSIONS_DIR:-/usr/share/wayland-sessions}
QB_GREETER_USER=${QB_GREETER_USER:-greeter}
QB_GREETER_LOGDIR=${QB_GREETER_LOGDIR:-/var/log/galaga}
QB_DID=() QB_SKIP=() QB_LAYOUTS=()

qb_add() { # a kernel cmdline -> the same line with our tokens appended. A token
    # already there is not repeated; a key already set to ANOTHER value
    # (loglevel=5) is the user's: it stays, ours is not added, and the note goes
    # to stderr so the substitution capturing this function's output stays clean
    local -a toks=() add=()
    read -ra toks <<<"$1"
    local w k t have kept keyed
    for w in "${QB_TOKENS[@]}"; do
        k=${w%%=*}; have=""; kept=""
        case "$w" in *=*) keyed=1 ;; *) keyed="" ;; esac # presence by key is
        # only for key=value tokens; a plain token counts by its exact self
        for t in "${toks[@]}"; do
            [ "$t" = "$w" ] && { have=1; break; }
            [ -n "$keyed" ] && [ "${t%%=*}" = "$k" ] && { have=foreign; kept=$t; }
        done
        case "$have" in
            1) ;;
            foreign) printf '  your %s stays, so %s is not added\n' "$kept" "$w" >&2 ;;
            *) add+=("$w") ;;
        esac
    done
    local out=("${toks[@]}" "${add[@]}")
    printf '%s' "${out[*]}"
}

qb_strip() { # a kernel cmdline -> the same line minus exactly our tokens (a key
    # set to a different value -- loglevel=5 -- is not ours and stays)
    local -a toks=() out=()
    read -ra toks <<<"$1"
    local t w drop
    for t in "${toks[@]}"; do
        drop=""
        for w in "${QB_TOKENS[@]}"; do [ "$t" = "$w" ] && { drop=1; break; }; done
        [ -z "$drop" ] && out+=("$t")
    done
    printf '%s' "${out[*]}"
}

qb_greeter_value() { # $1 on|off, $2 the greeter's command -> the command with
    # (or without) its output sent to the log. Only our exact suffix is ever
    # added or removed; a redirection of the user's own is not touched here
    local suffix=" >>$QB_GREETER_LOGDIR/greeter.log 2>&1"
    case "$1" in
        on) case "$2" in *">>"*) printf '%s' "$2" ;; *) printf '%s%s' "$2" "$suffix" ;; esac ;;
        off) case "$2" in *"$suffix") printf '%s' "${2%"$suffix"}" ;; *) printf '%s' "$2" ;; esac ;;
    esac
}

qb_xform_line() { # $1 kind (sdboot|limine|grub|greetd), $2 on|off, $3 line ->
    # the line, edited if it is one of the kind's own, untouched otherwise
    local kind=$1 mode=$2 line=$3 rest pre v inner q
    case "$kind" in
        sdboot)
            if [[ $line =~ ^options[[:space:]]+(.*)$ ]]; then
                rest=${BASH_REMATCH[1]}
                if [ "$mode" = on ]; then printf 'options %s' "$(qb_add "$rest")"
                else printf 'options %s' "$(qb_strip "$rest")"; fi
            else printf '%s' "$line"; fi ;;
        limine)
            if [[ $line =~ ^([[:space:]]*)(kernel_command_line|cmdline):[[:space:]]*(.*)$ ]]; then
                pre="${BASH_REMATCH[1]}${BASH_REMATCH[2]}: " rest=${BASH_REMATCH[3]}
                if [ "$mode" = on ]; then printf '%s%s' "$pre" "$(qb_add "$rest")"
                else printf '%s%s' "$pre" "$(qb_strip "$rest")"; fi
            else printf '%s' "$line"; fi ;;
        grub)
            if [[ $line =~ ^(GRUB_CMDLINE_LINUX_DEFAULT[[:space:]]*=[[:space:]]*)(.*)$ ]]; then
                pre=${BASH_REMATCH[1]} v=${BASH_REMATCH[2]} inner=$v q=""
                case "$v" in
                    \"*\") q='"'; inner=${v:1:${#v}-2} ;;
                    \'*\') q="'"; inner=${v:1:${#v}-2} ;;
                esac
                if [ "$mode" = on ]; then inner=$(qb_add "$inner")
                else inner=$(qb_strip "$inner"); fi
                # a bare value is one word by definition: if the result has
                # spaces it has to be quoted, or grub reads a different line
                [ -z "$q" ] && case "$inner" in *" "*) q='"' ;; esac
                printf '%s%s%s%s' "$pre" "$q" "$inner" "$q"
            else printf '%s' "$line"; fi ;;
        greetd)
            if [[ $line =~ ^(command[[:space:]]*=[[:space:]]*\")(.*)\"[[:space:]]*$ ]]; then
                pre=${BASH_REMATCH[1]} v=${BASH_REMATCH[2]}
                printf '%s%s"' "$pre" "$(qb_greeter_value "$mode" "$v")"
            else printf '%s' "$line"; fi ;;
        *) printf '%s' "$line" ;;
    esac
}

qb_backup() { # one-time backup beside the file, only if there is none yet: the
    # first copy is the pre-galaga original, later edits never overwrite it
    [ -e "$1.galaga-bak" ] || sudo cp -a "$1" "$1.galaga-bak"
}

qb_apply() { # $1 file, $2 kind, $3 on|off: rewrite the kind's lines in the file.
    # Returns 0 -- changed (would change, on a dry run), 2 -- already as asked,
    # 1 -- no such file. The transform runs line by line over a copy; the file
    # itself is replaced only when something actually moved
    local file=$1 kind=$2 mode=$3
    [ -f "$file" ] || return 1
    local tmp line
    tmp=$(mktemp)
    while IFS= read -r line || [ -n "$line" ]; do
        printf '%s\n' "$(qb_xform_line "$kind" "$mode" "$line")"
    done <"$file" >"$tmp"
    if cmp -s "$file" "$tmp"; then rm -f "$tmp"; return 2; fi
    if [ "$DRY" = 1 ]; then
        note "would rewrite the $kind line(s) in $file"
        rm -f "$tmp"
        return 0
    fi
    qb_backup "$file"
    sudo cp "$tmp" "$file"
    rm -f "$tmp"
    note "$file: $kind line(s) updated (backup: $file.galaga-bak)"
    return 0
}

qb_cmdline() { # $1 on|off -- layer 1: the kernel command line, in whichever
    # bootloader layouts this machine positively has
    local mode=$1 seen="" rc f lf ch same act=added
    [ "$mode" = off ] && act=removed
    # systemd-boot: the options line of every entry
    ch=0; same=0
    for f in "$QB_BOOT_DIR"/loader/entries/*.conf; do
        [ -f "$f" ] || continue
        grep -q '^options[[:space:]]' "$f" || continue
        seen=1
        rc=0; qb_apply "$f" sdboot "$mode" || rc=$?
        case "$rc" in 0) ch=1 ;; 2) same=1 ;; esac
    done
    if [ "$ch" = 1 ]; then QB_LAYOUTS+=(systemd-boot); QB_DID+=("kernel line: tokens $act in the systemd-boot entries")
    elif [ "$same" = 1 ]; then QB_LAYOUTS+=(systemd-boot); QB_SKIP+=("kernel line (systemd-boot): already as asked"); fi
    # limine: /boot/limine.conf, else the copy on the EFI partition
    lf=""
    if [ -f "$QB_BOOT_DIR/limine.conf" ]; then lf=$QB_BOOT_DIR/limine.conf
    elif [ -f "$QB_LIMINE_EFI" ]; then lf=$QB_LIMINE_EFI; fi
    if [ -n "$lf" ]; then
        seen=1
        if grep -Eq '^[[:space:]]*(kernel_command_line|cmdline):' "$lf"; then
            QB_LAYOUTS+=(limine)
            rc=0; qb_apply "$lf" limine "$mode" || rc=$?
            case "$rc" in
                0) QB_DID+=("kernel line: tokens $act in $lf") ;;
                2) QB_SKIP+=("kernel line (limine): already as asked") ;;
            esac
        else
            QB_SKIP+=("$lf has no kernel_command_line/cmdline line -- that layout is not recognized, left alone")
        fi
    fi
    # grub: the defaults file, then the generated config is rebuilt
    if [ -f "$QB_GRUB_CONF" ] && grep -q '^GRUB_CMDLINE_LINUX_DEFAULT[[:space:]]*=' "$QB_GRUB_CONF"; then
        seen=1; QB_LAYOUTS+=(grub)
        rc=0; qb_apply "$QB_GRUB_CONF" grub "$mode" || rc=$?
        case "$rc" in
            0) QB_DID+=("kernel line: tokens $act in $QB_GRUB_CONF, $QB_GRUB_CFG regenerated")
                run sudo grub-mkconfig -o "$QB_GRUB_CFG" ;;
            2) QB_SKIP+=("kernel line (grub): already as asked") ;;
        esac
    fi
    if [ ${#QB_LAYOUTS[@]} -gt 1 ]; then
        note "several bootloader layouts are present (${QB_LAYOUTS[*]}) -- each was edited; the tokens do nothing in one that never boots"
    fi
    if [ -z "${QB_LAYOUTS[*]}" ] && [ -z "$seen" ]; then
        # nothing editable matched: unified kernel images carry the line inside
        # the image itself, and anything else is a layout this does not know
        local uki=""
        for f in "$QB_BOOT_DIR"/*.efi "$QB_BOOT_DIR"/EFI/Linux/*.efi; do
            [ -f "$f" ] && { uki=1; break; }
        done
        if [ -n "$uki" ]; then
            QB_SKIP+=("kernel line: it is baked into the unified kernel images under $QB_BOOT_DIR -- nothing here can edit it, this layer is skipped")
        else
            QB_SKIP+=("kernel line: bootloader layout not recognized -- no changes made to it")
        fi
    fi
}

qb_detect_state() { # -> quiet | verbose | unknown on stdout: what the
    # machine's kernel line already says, read in the order qb_cmdline edits
    # them (the first positively recognized line speaks for the machine).
    # quiet means qb_add would change nothing on it -- our tokens are all
    # there; recognized without them is verbose; no recognized line at all is
    # unknown. qb_add's foreign-value notes are silenced: stdout is one word
    local f lf cmd=""
    for f in "$QB_BOOT_DIR"/loader/entries/*.conf; do
        [ -f "$f" ] || continue
        cmd=$(sed -n 's/^options[[:space:]][[:space:]]*//p' "$f" | head -n 1) || true
        [ -n "$cmd" ] && break
    done
    if [ -z "$cmd" ]; then
        lf=""
        if [ -f "$QB_BOOT_DIR/limine.conf" ]; then lf=$QB_BOOT_DIR/limine.conf
        elif [ -f "$QB_LIMINE_EFI" ]; then lf=$QB_LIMINE_EFI; fi
        if [ -n "$lf" ]; then
            cmd=$(sed -n 's/^[[:space:]]*\(kernel_command_line\|cmdline\):[[:space:]]*//p' "$lf" | head -n 1) || true
        fi
    fi
    if [ -z "$cmd" ] && [ -f "$QB_GRUB_CONF" ] && grep -q '^GRUB_CMDLINE_LINUX_DEFAULT[[:space:]]*=' "$QB_GRUB_CONF"; then
        cmd=$(sed -n 's/^GRUB_CMDLINE_LINUX_DEFAULT[[:space:]]*=[[:space:]]*//p' "$QB_GRUB_CONF" | head -n 1) || true
        case "$cmd" in
            \"*\") cmd=${cmd:1:${#cmd}-2} ;;
            \'*\') cmd=${cmd:1:${#cmd}-2} ;;
        esac
    fi
    if [ -z "$cmd" ]; then printf 'unknown'; return; fi
    if [ "$(qb_add "$cmd" 2>/dev/null)" = "$cmd" ]; then printf 'quiet'; else printf 'verbose'; fi
}

qb_boot_default() { # the guided boot-screen question's starting answer: the
    # machine's own state when it can be told, quiet when it cannot -- a fresh
    # machine gets the splash, a configured one is never surprised by Enter
    case "$(qb_detect_state)" in
        verbose) printf 'verbose' ;;
        *) printf 'quiet' ;;
    esac
}

qb_plymouth_layer() { # report only: 'splash' is on the line now, and the splash
    # shows only if plymouth is installed AND in the initramfs hooks -- neither
    # is installed or re-hooked from here, so a missing piece gets one honest line
    if ! command -v plymouth >/dev/null 2>&1; then
        QB_SKIP+=("splash: plymouth is not installed, so there is no splash screen -- the kernel text is off, but the console can still show between the firmware and the login face")
        return 0
    fi
    if [ ! -f "$QB_MKINITCPIO" ]; then
        QB_SKIP+=("splash: plymouth is installed, but there is no $QB_MKINITCPIO to check its hooks against")
        return 0
    fi
    local hooks
    hooks=$(sed -n 's/^[[:space:]]*HOOKS=(\(.*\))[[:space:]]*$/\1/p' "$QB_MKINITCPIO" | head -n 1)
    case " $hooks " in
        *" plymouth "*) QB_DID+=("splash: plymouth is installed and in the mkinitcpio hooks -- the splash will show") ;;
        *) QB_SKIP+=("splash: plymouth is installed but not in the mkinitcpio HOOKS -- the splash will not show until the hook is added and the initramfs rebuilt") ;;
    esac
}

qb_greeter_layer() { # $1 on|off -- layer 2: the greeter's own launch. greetd
    # runs our config's command on the console; wrapped, its output goes to a
    # log file instead. The log lives in a directory the greeter user owns --
    # /var/log itself is root's, and a redirection that cannot open would take
    # the greeter session down with it
    local mode=$1 conf=$QB_GREETD_CONF
    [ -f "$conf" ] || { QB_SKIP+=("greeter launch: no $conf -- the galaga greeter is not installed (./install.sh --greeter installs it)"); return 0; }
    local line value=""
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ $line =~ ^command[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*$ ]]; then value=${BASH_REMATCH[1]}; break; fi
    done <"$conf"
    case "$value" in
        "") QB_SKIP+=("greeter launch: no command line in $conf -- left alone"); return 0 ;;
        start-hyprland*) ;;
        *) QB_SKIP+=("greeter launch: the command in $conf is not the installer's start-hyprland launch -- left alone"); return 0 ;;
    esac
    if [ "$mode" = on ]; then
        case "$value" in
            *"$QB_GREETER_LOGDIR/greeter.log"*) QB_SKIP+=("greeter launch: already sends its output to the log"); return 0 ;;
            *">>"*) QB_SKIP+=("greeter launch: its output already goes somewhere else -- left as it is"); return 0 ;;
        esac
        if ! id -u "$QB_GREETER_USER" >/dev/null 2>&1; then
            QB_SKIP+=("greeter launch: there is no \"$QB_GREETER_USER\" user to own the log -- left unwrapped")
            return 0
        fi
        run sudo install -d -o "$QB_GREETER_USER" -g "$QB_GREETER_USER" -m 0755 "$QB_GREETER_LOGDIR"
    fi
    local rc=0
    qb_apply "$conf" greetd "$mode" || rc=$?
    case "$mode:$rc" in
        on:0) QB_DID+=("greeter launch: its output now goes to $QB_GREETER_LOGDIR/greeter.log instead of the console") ;;
        on:2) QB_SKIP+=("greeter launch: already sends its output to the log") ;;
        off:0) QB_DID+=("greeter launch: its output is back on the console") ;;
        off:2) case "$value" in
            *">>"*) QB_SKIP+=("greeter launch: the redirection there is not ours -- left alone") ;;
            *) QB_SKIP+=("greeter launch: it is not wrapped -- nothing to undo") ;;
        esac ;;
    esac
    return 0
}

qb_desktop_key() { # $1 a .desktop file, $2 a key -> its value in [Desktop Entry]
    awk -v k="$2=" '/^\[/ { e = ($0 == "[Desktop Entry]") } e && index($0, k) == 1 { sub(k, ""); print; exit }' "$1"
}

qb_session_layer() { # $1 on|off -- layer 3: the user session. The block after
    # login ("Selected compositor ID...", "Created unit...", "Starting
    # wayland-session...") is the session command printing on the console. On:
    # a galaga.desktop is installed next to the uwsm Hyprland entry, running
    # the SAME command with its output appended to a log in the user's state
    # dir; the greeter face prefers it while it exists (greet.qml), so off --
    # deleting the file -- is the whole revert, nothing else to unwind
    local mode=$1 target=$QB_SESSIONS_DIR/galaga.desktop
    if [ "$mode" = off ]; then
        if [ -e "$target" ]; then
            run sudo rm "$target"
            QB_DID+=("quiet session removed: $target -- the face picks the uwsm entry again")
        else
            QB_SKIP+=("quiet session: $target is not installed")
        fi
        return 0
    fi
    # the entry to wrap, found by the face's own rule: Exec mentions uwsm,
    # name+exec mention hyprland
    local f name ex src="" src_exec=""
    for f in "$QB_SESSIONS_DIR"/*.desktop; do
        [ -r "$f" ] || continue
        [ "$f" = "$target" ] && continue
        ex=$(qb_desktop_key "$f" Exec)
        [ -n "$ex" ] || continue
        case "$ex" in *uwsm* | *UWSM*) ;; *) continue ;; esac
        name=$(qb_desktop_key "$f" Name)
        case "$name $ex" in *[Hh]yprland*) src=$f; src_exec=$ex; break ;; esac
    done
    if [ -z "$src" ]; then
        QB_SKIP+=("quiet session: no uwsm Hyprland entry in $QB_SESSIONS_DIR to wrap -- the face's own pick is unchanged")
        return 0
    fi
    case "$src_exec" in
        *\'*) QB_SKIP+=("quiet session: the Exec in $src quotes in a way the wrap cannot carry -- left alone"); return 0 ;;
    esac
    local names content
    names=$(qb_desktop_key "$src" DesktopNames)
    content="[Desktop Entry]
Name=Hyprland (quiet)
Comment=Hyprland through uwsm, with the session's output kept in a log file
Exec=sh -c 'mkdir -p \"\$HOME/.local/state/galaga\"; exec $src_exec >>\"\$HOME/.local/state/galaga/session.log\" 2>&1'
Type=Application"
    [ -n "$names" ] && content+=$'\n'"DesktopNames=$names"
    if [ -f "$target" ] && [ "$(cat "$target")" = "$content" ]; then
        QB_SKIP+=("quiet session: $target is already installed")
        return 0
    fi
    if [ "$DRY" = 1 ]; then
        note "would install $target (it wraps $src)"
    else
        printf '%s\n' "$content" | sudo tee "$target" >/dev/null
    fi
    QB_DID+=("quiet session: $target wraps $src, output to ~/.local/state/galaga/session.log")
}

quiet_boot() { # $1 on|off -- the summary prints what changed and what was left
    # alone and why; nothing here claims a change it did not make
    local mode=$1 x didword=changed
    QB_DID=(); QB_SKIP=(); QB_LAYOUTS=()
    if [ "$mode" = on ]; then say "quiet boot: the console stays dark"
    else say "quiet boot off: the boot text comes back"; fi
    qb_cmdline "$mode"
    [ "$mode" = on ] && qb_plymouth_layer
    qb_greeter_layer "$mode"
    qb_session_layer "$mode"
    [ "$DRY" = 1 ] && didword="would change"
    for x in "${QB_DID[@]}"; do note "$didword: $x"; done
    for x in "${QB_SKIP[@]}"; do note "left alone: $x"; done
    if [ "$mode" = on ]; then
        note "one heads-up: ./install.sh --greeter rewrites /etc/greetd/config.toml from the repo copy -- re-run --quiet-boot after it"
        say "takes effect from the next boot. undo: ./install.sh --no-quiet-boot"
    else say "the boot text is back from the next boot"; fi
}
# ---- end quiet boot --------------------------------------------------------------


[ "$EUID" -eq 0 ] && { echo "run as your user, sudo will ask by itself"; exit 1; }

# --browsers <list> rides along with the guided flow or --with: lift it out first,
# the case below keeps its one-mode shape. No --browsers -- the question is asked
# (or the default answers, on a scripted run)
_args=()
while [ $# -gt 0 ]; do
    case "$1" in
        --browsers) BWITH="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
        *) _args+=("$1"); shift ;;
    esac
done
set -- "${_args[@]}"

case "${1:-}" in
    --links) links; browser_cleanup; flatpak_gtk; tmux_theme ;; # on any distribution (NixOS, Fedora...): packages are up to you then, list in README
    --greeter) command -v pacman >/dev/null || { echo "the greeter step installs greetd with pacman (Arch only)"; exit 1; }
        greeter ;;
    --quiet-boot) [ "${2:-}" = --dry-run ] && DRY=1; quiet_boot on ;;
    --no-quiet-boot) [ "${2:-}" = --dry-run ] && DRY=1; quiet_boot off ;;
    --dry-run) command -v pacman >/dev/null || { echo "I only install packages on Arch; on another distribution: $0 --links"; exit 1; }
        DRY=1; install_flow ;;
    --update) update ;;
    --update-rest) update_rest "${2:-}" ;;
    --fix-plasma) fix_plasma ;;
    --uninstall) uninstall ;;
    ""|--with) command -v pacman >/dev/null || { echo "I only install packages on Arch; on another distribution: $0 --links"; exit 1; }
        [ "${1:-}" = --with ] && WITH="${*:2}" # both comma- and space-separated
        install_flow ;;
    *) echo "usage: $0 [--with telegram,spotify,clash,pywalfox,warp,overskride] [--browsers firefox,zen,chromium,brave,vivaldi] | --links | --greeter | --quiet-boot | --no-quiet-boot | --dry-run | --update | --fix-plasma | --uninstall]"; exit 1 ;;
esac
