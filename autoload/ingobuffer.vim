" ingobuffer.vim: Custom buffer functions.
"
" DEPENDENCIES:
"   - ingofile.vim autoload script (for ingobuffer#MakeScratchBuffer())
"
" Copyright: (C) 2009-2012 Ingo Karkat
"   The VIM LICENSE applies to this script; see ':help copyright'.
"
" Maintainer:	Ingo Karkat <ingo@karkat.de>
"
" REVISION	DATE		REMARKS
"	015	18-May-2012	Move ingobuffer#CombineToFilespec() and
"				ingobuffer#MakeTempfile() to ingofile.vim
"				autoload script.
"	014	26-Mar-2012	Add ingobuffer#IsEmptyBuffer(), copied from
"				ingotemplates.vim.
"	013	26-Oct-2011	Also switch algorithm for
"				ingobuffer#ExecuteInVisibleBuffer(), because
"				:hide may destroy the current buffer when
"				'bufhidden' is set. (This happened in the blame
"				buffer of vcscommand.vim).
"	012	03-Oct-2011	Switch algorithm for
"				ingobuffer#ExecuteInTempBuffer() from switching
"				buffers to new split buffer, since the former
"				had a noticable delay when in a long Vimscript
"				file, due to re-sync of syntax highlighting.
"	011	01-Oct-2011	Factor out more generic
"				ingobuffer#NextBracketedFilename().
"	010	27-Sep-2011	Add ingobuffer#ExecuteInTempBuffer(), and
"				ingobuffer#CallInTempBuffer().
"				Also implement ingobuffer#CallInVisibleBuffer()
"				in the same style.
"	009	09-Jul-2011	Have somehow written ingobuffer#MakeTempfile()
"				without knowledge of the built-in tempname().
"				Now use that as the primary source of a temp
"				directory, and only use the other locations as
"				(probably unnecessary) fallbacks.
"	008	12-Apr-2011	Add ingobuffer#ExecuteInVisibleBuffer() for
"				:AutoSave command.
"	007	31-Mar-2011	ingobuffer#MakeScratchBuffer() only deletes the
"				first line in the scratch buffer if it is
"				actually empty.
"				FIX: Need to check the buftype also when a
"				window is visible that shows a buffer with the
"				scratch filename. Otherwise, a buffer containing
"				a normal file may be re-used as a scratch
"				buffer.
"				Also allow scratch buffer names like
"				"[Messages]", not just "Messages [Scratch]" in
"				ingobuffer#NextScratchFilename().
"				Minor: 'buftype' can only contain one particular
"				word, change regexp-match to exact match.
"	006	17-Jan-2011	Added $TMPDIR to ingobuffer#MakeTempfile().
"	005	02-Mar-2010	ENH: ingobuffer#CombineToFilespec() allows
"				multiple filenames and passing in a single list
"				of filespec fragments. Improved detection of
"				desired path separator and falling back to
"				system default based on 'shellslash' setting.
"	004	15-Oct-2009	ENH: ingobuffer#MakeScratchBuffer() now allows
"				to omit (via empty string) the a:scratchCommand
"				Ex command, and will then keep the scratch
"				buffer writable.
"	003	04-Sep-2009	ENH: If a:scratchIsFile is false and
"				a:scratchDirspec is empty, there will be only
"				one scratch buffer with the same
"				a:scratchFilename, regardless of the scratch
"				buffer's directory path. This also fixes Vim
"				errors on the :file command when s:Bufnr() has
"				determined that there is no existing buffer,
"				when in fact there is.
"				Replaced ':normal ...dd' with :delete, and not
"				clobbering the unnamed register any more.
"	002	01-Sep-2009	Added ingobuffer#MakeTempfile().
"	001	05-Jan-2009	file creation

function! ingobuffer#IsEmptyBuffer()
    return line('$') == 1 && empty(getline(1))
endfunction

function! ingobuffer#NextBracketedFilename( filespec, template )
    let l:templateExpr = '\V\C'. escape(a:template, '\') . '\m'
    if a:filespec !~# '\%(^\| \)\[' . l:templateExpr . ' \?\d*\]$'
	return a:filespec . (empty(a:filespec) ? '' : ' ') . '['. a:template . ']'
    elseif a:filespec !~# '\%(^\| \)\[' . l:templateExpr . ' \?\d\+\]$'
	return substitute(a:filespec, '\]$', '1]', '')
    else
	let l:number = matchstr(a:filespec, '\%(^\| \)\[' . l:templateExpr . ' \?\zs\d\+\ze\]$')
	return substitute(a:filespec, '\d\+\]$', (l:number + 1) . ']', '')
    endif
endfunction
function! ingobuffer#NextScratchFilename( filespec )
    return ingobuffer#NextBracketedFilename(a:filespec, 'Scratch')
endfunction
function! s:Bufnr( dirspec, filename, isFile )
    if empty(a:dirspec) && ! a:isFile
	" This scratch buffer does not behave like a file and is not tethered to
	" a particular directory; there should be only one scratch buffer with
	" this name in the Vim session.
	" Do a partial search for the buffer name matching any file name in any
	" directory.
	return bufnr('/'. escapings#bufnameescape(a:filename, 0) . '$')
    else
	return bufnr(
	\   escapings#bufnameescape(
	\	fnamemodify(
	\	    ingofile#CombineToFilespec(a:dirspec, a:filename),
	\	    '%:p'
	\	)
	\   )
	\)
    endif
endfunction
function! s:ChangeDir( dirspec )
    if empty( a:dirspec )
	return
    endif
    execute 'lcd ' . escapings#fnameescape(a:dirspec)
endfunction
function! s:BufType( scratchIsFile )
    return (a:scratchIsFile ? 'nowrite' : 'nofile')
endfunction
function! ingobuffer#MakeScratchBuffer( scratchDirspec, scratchFilename, scratchIsFile, scratchCommand, windowOpenCommand )
"*******************************************************************************
"* PURPOSE:
"   Create (or re-use an existing) scratch buffer (i.e. doesn't correspond to a
"   file on disk, but can be saved as such).
"   To keep the scratch buffer (and create a new scratch buffer on the next
"   invocation), rename the current scratch buffer via ':file <newname>', or
"   make it a normal buffer via ':setl buftype='.
"
"* ASSUMPTIONS / PRECONDITIONS:
"   None.
"* EFFECTS / POSTCONDITIONS:
"   Creates or opens scratch buffer and loads it in a window (as specified by
"   a:windowOpenCommand) and activates that window.
"* INPUTS:
"   a:scratchDirspec	Local working directory for the scratch buffer
"			(important for :! scratch commands). Pass empty string
"			to maintain the current CWD as-is. Pass '.' to maintain
"			the CWD but also fix it via :lcd.
"			(Attention: ':set autochdir' will reset any CWD once the
"			current window is left!) Pass the getcwd() output if
"			maintaining the current CWD is important for
"			a:scratchCommand.
"   a:scratchFilename	The name for the scratch buffer, so it can be saved via
"			either :w! or :w <newname>.
"   a:scratchIsFile	Flag whether the scratch buffer should behave like a
"			file (i.e. adapt to changes in the global CWD), or not.
"			If false and a:scratchDirspec is empty, there will be
"			only one scratch buffer with the same a:scratchFilename,
"			regardless of the scratch buffer's directory path.
"   a:scratchCommand	Ex command(s) to populate the scratch buffer, e.g.
"			":1read myfile". Use :1read so that the first empty line
"			will be kept (it is deleted automatically), and there
"			will be no trailing empty line.
"			Pass empty string if you want to populate the scratch
"			buffer yourself.
"   a:windowOpenCommand	Ex command to open the scratch window, e.g. :vnew or
"			:topleft new.
"* RETURN VALUES:
"   Indicator whether the scratch buffer has been opened:
"   0	Failed to open scratch buffer.
"   1	Already in scratch buffer window.
"   2	Jumped to open scratch buffer window.
"   3	Loaded existing scratch buffer in new window.
"   4	Created scratch buffer in new window.
"*******************************************************************************
    let l:currentWinNr = winnr()
    let l:status = 0

    let l:scratchBufnr = s:Bufnr(a:scratchDirspec, a:scratchFilename, a:scratchIsFile)
    let l:scratchWinnr = bufwinnr(l:scratchBufnr)
"****D echomsg '**** bufnr=' . l:scratchBufnr 'winnr=' . l:scratchWinnr
    if l:scratchWinnr == -1
	if l:scratchBufnr == -1
	    execute a:windowOpenCommand
	    " Note: The directory must already be changed here so that the :file
	    " command can set the correct buffer filespec.
	    call s:ChangeDir(a:scratchDirspec)
	    execute 'silent keepalt file ' . escapings#fnameescape(a:scratchFilename)
	    let l:status = 4
	elseif getbufvar(l:scratchBufnr, '&buftype') ==# s:BufType(a:scratchIsFile)
	    execute a:windowOpenCommand
	    execute l:scratchBufnr . 'buffer'
	    let l:status = 3
	else
	    " A buffer with the scratch filespec is already loaded, but it
	    " contains an existing file, not a scratch file. As we don't want to
	    " jump to this existing file, try again with the next scratch
	    " filename.
	    return ingobuffer#MakeScratchBuffer(a:scratchDirspec, ingobuffer#NextScratchFilename(a:scratchFilename), a:scratchIsFile, a:scratchCommand, a:windowOpenCommand)
	endif
    else
	if getbufvar(l:scratchBufnr, '&buftype') !=# s:BufType(a:scratchIsFile)
	    " A window with the scratch filespec is already visible, but its
	    " buffer contains an existing file, not a scratch file. As we don't
	    " want to jump to this existing file, try again with the next
	    " scratch filename.
	    return ingobuffer#MakeScratchBuffer(a:scratchDirspec, ingobuffer#NextScratchFilename(a:scratchFilename), a:scratchIsFile, a:scratchCommand, a:windowOpenCommand)
	elseif l:scratchWinnr == l:currentWinNr
	    let l:status = 1
	else
	    execute l:scratchWinnr . 'wincmd w'
	    let l:status = 2
	endif
    endif

    call s:ChangeDir(a:scratchDirspec)
    setlocal noreadonly
    silent %delete _
    " Note: ':silent' to suppress the "--No lines in buffer--" message.

    if ! empty(a:scratchCommand)
	execute a:scratchCommand
	" ^ Keeps the existing line at the top of the buffer, if :1{cmd} is used.
	" v Deletes it.
	if empty(getline(1)) | silent 1delete _ | endif
	" Note: ':silent' to suppress deletion message if ':set report=0'.

	setlocal readonly
    endif

    execute 'setlocal buftype=' . s:BufType(a:scratchIsFile)
    setlocal bufhidden=wipe nobuflisted noswapfile
    return l:status
endfunction



function! ingobuffer#ExecuteInVisibleBuffer( bufnr, command )
"******************************************************************************
"* PURPOSE:
"   Invoke an Ex command in a visible buffer.
"   Some commands (e.g. :update) operate in the context of the current buffer
"   and must therefore be visible in a window to be invoked. This function
"   ensures that the passed command is executed in the context of the passed
"   buffer number.

"* ASSUMPTIONS / PRECONDITIONS:
"	? List of any external variable, control, or other element whose state affects this procedure.
"* EFFECTS / POSTCONDITIONS:
"   The current window and buffer loaded into it remain the same.
"* INPUTS:
"   a:bufnr Buffer number of an existing buffer where the function should be
"   executed in.
"   a:command	Ex command to be invoked.
"* RETURN VALUES:
"   None.
"******************************************************************************
    let l:winnr = bufwinnr(a:bufnr)
    if l:winnr == -1
	" The buffer is hidden. Make it visible to execute the passed function.
	" Use a temporary split window as ingobuffer#ExecuteInTempBuffer() does,
	" for all the reasons outlined there.
	let l:originalWindowLayout = winrestcmd()
	    execute 'noautocmd silent keepalt leftabove sbuffer' a:bufnr
	try
	    execute a:command
	finally
	    noautocmd silent close
	    silent! execute l:originalWindowLayout
	endtry
    else
	" The buffer is visible in at least one window on this tab page.
	let l:currentWinNr = winnr()
	execute l:winnr . 'wincmd w'
	try
	    execute a:command
	finally
	    execute l:currentWinNr . 'wincmd w'
	endtry
    endif
endfunction
function! ingobuffer#CallInVisibleBuffer( bufnr, Funcref, arguments )
    return ingobuffer#ExecuteInVisibleBuffer(a:bufnr, 'call call(' . string(a:Funcref) . ',' . string(a:arguments) . ')')
endfunction

function! ingobuffer#ExecuteInTempBuffer( command, ...)
"******************************************************************************
"* PURPOSE:
"   Invoke an Ex command in an empty temporary scratch buffer and return the
"   contents of the buffer after the execution.
"
"* ASSUMPTIONS / PRECONDITIONS:
"   None.
"* EFFECTS / POSTCONDITIONS:
"   None.
"* INPUTS:
"   a:command	Ex command to be invoked.
"   a:isIgnoreOutput	Flag whether to skip capture of the scratch buffer
"			contents and just execute a:command for its side
"			effects.
"* RETURN VALUES:
"   Contents of the buffer.
"******************************************************************************
    " It's hard to create a temp buffer in a safe way without side effects.
    " Switching the buffer can change the window view, may have a noticable
    " delay even with autocmds suppressed (maybe due to 'autochdir', or just a
    " sync in syntax highlighting), or even destroy the buffer ('bufhidden').
    " Splitting changes the window layout; there may not be room for another
    " window or tab. And autocmds may do all sorts of uncontrolled changes.
    let l:originalWindowLayout = winrestcmd()
	noautocmd silent keepalt leftabove 1new
	let l:tempBufNr = bufnr('')
    try
	silent execute a:command
	if ! a:0 || ! a:1
	    return join(getline(1, line('$')), "\n")
	endif
    finally
	noautocmd silent execute l:tempBufNr . 'bdelete!'
	silent! execute l:originalWindowLayout
    endtry
endfunction
function! ingobuffer#CallInTempBuffer( Funcref, arguments, ... )
    return call('ingobuffer#ExecuteInTempBuffer', ['call call(' . string(a:Funcref) . ',' . string(a:arguments) . ')'] + a:000)
endfunction

" vim: set ts=8 sts=4 sw=4 noexpandtab ff=unix fdm=syntax :
