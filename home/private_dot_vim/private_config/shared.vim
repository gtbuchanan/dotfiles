""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" This file should only contain syntax/settings supported by Vim & VsVim "
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Show line numbers
set number

" Wrap text automatically
set textwidth=100

" Sane leader key
nnoremap <SPACE> <Nop>
let g:mapleader=" "

" Copy to clipboard in Visual/Select mode
vnoremap <C-c> "+y
vnoremap <C-x> "+x
