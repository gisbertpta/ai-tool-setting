" ~/.vimrc — minimal config for the AI sandbox devcontainer

" Start from vim's defaults (skipped automatically once a ~/.vimrc exists)
unlet! skip_defaults_vim
source $VIMRUNTIME/defaults.vim

set encoding=utf-8
set number
set hidden
set laststatus=2
set ignorecase smartcase
set hlsearch
set expandtab shiftwidth=4 softtabstop=4
set autoread
set mouse=

" Persistent undo (lost on rebuild, survives editor restarts)
set undofile
set undodir=~/.local/state/vim/undo//
silent! call mkdir(expand('~/.local/state/vim/undo'), 'p', 0700)

" <Space><Space> clears search highlighting
nnoremap <silent> <Space><Space> :nohlsearch<CR>

" fzf (Debian package): :FZF opens a fuzzy file finder
silent! source /usr/share/doc/fzf/examples/fzf.vim
