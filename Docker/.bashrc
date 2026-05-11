# -------------------------------------------------
# Aliases
# -------------------------------------------------
alias ll='ls -alF'
alias la='ls -A'
alias gs='git status'
alias cf='clang-format -i'
alias cfd='clang-format'

# -------------------------------------------------
# Go environment
# -------------------------------------------------
export GOPATH="$HOME/go"
export PATH="$PATH:/usr/local/go/bin:$GOPATH/bin"

# -------------------------------------------------
# General quality-of-life
# -------------------------------------------------
export EDITOR=vim