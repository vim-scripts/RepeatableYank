" RepeatableYank.vim: Repeatable appending yank to a named register.
"
" DEPENDENCIES:
"   - Requires Vim 7.0 or higher.
"   - RepeatableYank.vim autoload script.
"
" Copyright: (C) 2011-2012 Ingo Karkat
"   The VIM LICENSE applies to this script; see ':help copyright'.
"
" Maintainer:	Ingo Karkat <ingo@karkat.de>
"
" REVISION	DATE		REMARKS
"   1.10.005	26-Dec-2012	ENH: Add alternative gly mapping to yank as new
"				line.
"   1.00.004	22-Oct-2011	Pull <SID>Reselect into the main mapping (the
"				final <Esc> is important to "seal" the visual
"				selection and make it recallable via gv),
"				because it doesn't multiply the selection size
"				when [count] is given.
"	003	21-Oct-2011	Introduce g:RepeatableYank_DefaultRegister to
"				avoid error when using gy for the first time
"				without specifying a register.
"	002	21-Oct-2011	Note: <SID>Reselect swallows register repeat set
"				by repeat.vim. This doesn't matter here, because
"				we don't invoke repeat#setreg() and the default
"				register is treated as an append, anyway.
"				However, let's get rid of the
"				<SID>RepeatableYankVisual mapping and duplicate
"				the short invocation instead.
"	001	21-Oct-2011	Split off functions to autoload file.
"				file creation

" Avoid installing twice or when in unsupported Vim version.
if exists('g:loaded_RepeatableYank') || (v:version < 700)
    finish
endif
let g:loaded_RepeatableYank = 1
let s:save_cpo = &cpo
set cpo&vim

"- configuration ---------------------------------------------------------------

if ! exists('g:RepeatableYank_DefaultRegister')
    let g:RepeatableYank_DefaultRegister = 'a'
endif


"- mappings --------------------------------------------------------------------

" This mapping repeats naturally, because it just sets global things, and Vim is
" able to repeat the g@ on its own.
nnoremap <expr> <Plug>RepeatableYankOperator       RepeatableYank#OperatorExpression()
nnoremap <expr> <Plug>RepeatableYankAsLineOperator RepeatableYank#OperatorAsLineExpression()
" This mapping needs repeat.vim to be repeatable, because it contains of
" multiple steps (visual selection + yank command inside
" RepeatableYank#Operator).
nnoremap <silent> <Plug>RepeatableYankLine         :<C-u>call RepeatableYank#SetRegister()<Bar>execute 'normal! V' . v:count1 . "_\<lt>Esc>"<Bar>call RepeatableYank#Operator('visual', "\<lt>Plug>RepeatableYankLine")<CR>
" Repeat not defined in visual mode, but enabled through visualrepeat.vim.
vnoremap <silent> <Plug>RepeatableYankVisual       :<C-u>call RepeatableYank#SetRegister()<Bar>call RepeatableYank#Operator('visual', "\<lt>Plug>RepeatableYankVisual")<CR>
vnoremap <silent> <Plug>RepeatableYankAsLineVisual :<C-u>call RepeatableYank#SetRegister()<Bar>call RepeatableYank#OperatorAsLine('visual', "\<lt>Plug>RepeatableYankAsLineVisual")<CR>

" A normal-mode repeat of the visual mapping is triggered by repeat.vim. It
" establishes a new selection at the cursor position, of the same mode and size
" as the last selection.
"   If [count] is given, the size is multiplied accordingly. This has the side
"   effect that a repeat with [count] will persist the expanded size, which is
"   different from what the normal-mode repeat does (it keeps the scope of the
"   original command).
" On repetition, v:register will contain the unnamed register (because we do not
" use repeat#setreg(), and therefore the used register isn't repeated), and that
" will trigger the desired append to s:activeRegister.
nnoremap <silent> <Plug>RepeatableYankVisual
\ :<C-u>call RepeatableYank#SetRegister()<Bar>
\execute 'normal!' v:count1 . 'v' . (visualmode() !=# 'V' && &selection ==# 'exclusive' ? ' ' : ''). "\<lt>Esc>"<Bar>
\call RepeatableYank#Operator('visual', "\<lt>Plug>RepeatableYankVisual")<CR>
nnoremap <silent> <Plug>RepeatableYankAsLineVisual
\ :<C-u>call RepeatableYank#SetRegister()<Bar>
\execute 'normal!' v:count1 . 'v' . (visualmode() !=# 'V' && &selection ==# 'exclusive' ? ' ' : ''). "\<lt>Esc>"<Bar>
\call RepeatableYank#OperatorAsLine('visual', "\<lt>Plug>RepeatableYankAsLineVisual")<CR>

if ! hasmapto('<Plug>RepeatableYankOperator', 'n')
    nmap gy <Plug>RepeatableYankOperator
endif
if ! hasmapto('<Plug>RepeatableYankLine', 'n')
    nmap gyy <Plug>RepeatableYankLine
endif
if ! hasmapto('<Plug>RepeatableYankVisual', 'x')
    xmap gy <Plug>RepeatableYankVisual
endif
if ! hasmapto('<Plug>RepeatableYankAsLineOperator', 'n')
    nmap gly <Plug>RepeatableYankAsLineOperator
endif
if ! hasmapto('<Plug>RepeatableYankAsLineVisual', 'x')
    xmap gly <Plug>RepeatableYankAsLineVisual
endif

let &cpo = s:save_cpo
unlet s:save_cpo
" vim: set ts=8 sts=4 sw=4 noexpandtab ff=unix fdm=syntax :
