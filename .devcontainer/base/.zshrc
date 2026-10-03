# ~/.zshrc — minimal config for the AI sandbox devcontainer

# ── History ───────────────────────────────────────────────────────────────────
HISTFILE=~/.local/state/zsh/history   # named volume, survives rebuilds
HISTSIZE=5000
SAVEHIST=5000
setopt HIST_IGNORE_DUPS SHARE_HISTORY

# ── Prompt with git branch ────────────────────────────────────────────────────
autoload -Uz vcs_info
precmd() { vcs_info }
zstyle ':vcs_info:git:*' formats ' (%b)'
setopt PROMPT_SUBST
PROMPT='%F{cyan}%n@%m%f:%F{yellow}%~%f%F{green}${vcs_info_msg_0_}%f$ '

# ── Completion ────────────────────────────────────────────────────────────────
autoload -Uz compinit && compinit

# ── Aliases ───────────────────────────────────────────────────────────────────
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias g='git'
