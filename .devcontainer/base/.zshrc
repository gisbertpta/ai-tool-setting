# ~/.zshrc — minimal config for the AI sandbox devcontainer
#
# Agent CLIs run their commands in this shell and pick up its aliases and
# functions: only add new short names here, never redefine core commands
# (rm -i, cat=bat, ...), or agent commands may hang or misbehave.

# ── History ───────────────────────────────────────────────────────────────────
HISTFILE=~/.local/state/zsh/history   # named volume, survives rebuilds
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS EXTENDED_HISTORY

# ── Prompt with git branch ────────────────────────────────────────────────────
autoload -Uz vcs_info
precmd() { vcs_info }
zstyle ':vcs_info:git:*' formats ' (%b)'
setopt PROMPT_SUBST
PROMPT='%F{cyan}%n@%m%f:%F{yellow}%~%f%F{green}${vcs_info_msg_0_}%f$ '

# ── Completion: menu, case-insensitive, colors ────────────────────────────────
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
setopt AUTO_CD

# ── Aliases ───────────────────────────────────────────────────────────────────
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias g='git'

# ── Interactive only: vi mode, keys, plugins ──────────────────────────────────
if [[ -o interactive ]]; then
  # vi mode; no delay after <Esc>
  bindkey -v
  KEYTIMEOUT=1

  # Backspace / ^W / ^U work across the insert start, like in vim with bs=2
  bindkey -M viins '^?' backward-delete-char
  bindkey -M viins '^H' backward-delete-char
  bindkey -M viins '^W' backward-kill-word
  bindkey -M viins '^U' backward-kill-line

  # Up/down (and k/j in normal mode) search history by the typed prefix
  autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
  zle -N up-line-or-beginning-search
  zle -N down-line-or-beginning-search
  bindkey -M viins '^[[A' up-line-or-beginning-search
  bindkey -M viins '^[[B' down-line-or-beginning-search
  bindkey -M vicmd 'k' up-line-or-beginning-search
  bindkey -M vicmd 'j' down-line-or-beginning-search

  # 'v' in normal mode opens the command line in vim
  autoload -Uz edit-command-line
  zle -N edit-command-line
  bindkey -M vicmd 'v' edit-command-line

  # Cursor shape: beam in insert mode, block in normal mode
  zle-keymap-select() {
    [[ $KEYMAP == vicmd ]] && print -n '\e[2 q' || print -n '\e[6 q'
  }
  zle-line-init() { print -n '\e[6 q' }
  zle -N zle-keymap-select
  zle -N zle-line-init

  # fzf: ^R history, ^T files, Alt-C cd (bound in vi keymaps too)
  source /usr/share/doc/fzf/examples/key-bindings.zsh
  source /usr/share/doc/fzf/examples/completion.zsh

  # Grey history suggestion; accept with → or ^F
  source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
  bindkey -M viins '^F' autosuggest-accept

  # Must be sourced last
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
