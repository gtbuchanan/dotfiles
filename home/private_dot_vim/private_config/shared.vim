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

" Yank to clipboard
vnoremap <C-c> "+y
nnoremap <leader>y "+y
xnoremap <leader>y "+y
nnoremap <leader>Y "+Y
xnoremap <leader>Y "+Y

" Delete to clipboard
vnoremap <C-x> "+x
nnoremap <leader>x "+x
xnoremap <leader>x "+x

" Paste from clipboard
vnoremap <C-v> "+p
inoremap <C-v> <C-o>"+p
nnoremap <leader>p "+p
xnoremap <leader>p "+p
nnoremap <leader>P "+P
xnoremap <leader>P "+P
