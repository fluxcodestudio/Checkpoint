" Checkpoint - Autoload Functions
" Version: 1.2.0

" ==============================================================================
" UTILITY FUNCTIONS
" ==============================================================================

" Get bin path
function! s:GetBinPath()
  if g:backup_bin_path != ''
    return g:backup_bin_path
  endif

  " Try common locations
  let l:locations = [
        \ $CLAUDECODE_BACKUP_ROOT . '/bin',
        \ expand('~/.claudecode-backups/bin'),
        \ expand('~/ClaudeCode-Project-Backups/bin')
        \ ]

  for l:path in l:locations
    if isdirectory(l:path)
      return l:path
    endif
  endfor

  echohl WarningMsg
  echo 'Backup bin directory not found. Set g:backup_bin_path'
  echohl None
  return ''
endfunction

" Execute backup script
function! s:ExecuteScript(script, args)
  let l:bin_path = s:GetBinPath()
  if l:bin_path == ''
    return
  endif

  let l:cmd = shellescape(l:bin_path . '/' . a:script) . ' ' . a:args
  return system(l:cmd)
endfunction

" Show notification
function! s:Notify(message, ...)
  if !g:backup_notifications
    return
  endif

  let l:type = a:0 > 0 ? a:1 : 'info'

  " Use Neovim floating window if available
  if has('nvim') && exists('*nvim_open_win')
    call s:NotifyFloating(a:message, l:type)
  else
    " Fallback to echo
    if l:type == 'error'
      echohl ErrorMsg
    elseif l:type == 'warning'
      echohl WarningMsg
    else
      echohl None
    endif
    echo a:message
    echohl None
  endif
endfunction

" Neovim floating notification
function! s:NotifyFloating(message, type)
  let l:buf = nvim_create_buf(v:false, v:true)
  let l:lines = split(a:message, "\n")
  call nvim_buf_set_lines(l:buf, 0, -1, v:true, l:lines)

  let l:width = max(map(copy(l:lines), 'len(v:val)')) + 4
  let l:height = len(l:lines) + 2

  let l:opts = {
        \ 'relative': 'editor',
        \ 'width': l:width,
        \ 'height': l:height,
        \ 'col': &columns - l:width - 2,
        \ 'row': 1,
        \ 'anchor': 'NE',
        \ 'style': 'minimal',
        \ 'border': 'rounded'
        \ }

  let l:win = nvim_open_win(l:buf, v:false, l:opts)

  " Auto-close after 3 seconds
  call timer_start(3000, {-> nvim_win_close(l:win, v:true)})
endfunction

" ==============================================================================
" DEBOUNCE MECHANISM
" ==============================================================================

let s:last_trigger_time = 0

function! s:ShouldTrigger()
  let l:now = localtime()
  let l:elapsed = l:now - s:last_trigger_time

  if l:elapsed >= g:backup_trigger_delay / 1000
    let s:last_trigger_time = l:now
    return 1
  endif
  return 0
endfunction

" ==============================================================================
" COMMAND IMPLEMENTATIONS
" ==============================================================================

" Show backup status
function! backup#Status()
  let l:output = s:ExecuteScript('backup-status.sh', '')

  " Open in new split
  new
  setlocal buftype=nofile
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal nowrap
  setlocal filetype=backupstatus

  " Insert output
  call setline(1, split(l:output, "\n"))

  " Make read-only
  setlocal nomodifiable

  " Add keybinding to close
  nnoremap <buffer> q :q<CR>
  nnoremap <buffer> <Esc> :q<CR>

  " Resize to fit content
  execute 'resize ' . min([line('$') + 1, 40])
endfunction

" Trigger backup now
function! backup#Now()
  call s:Notify('Triggering backup...', 'info')

  let l:output = s:ExecuteScript('backup-now.sh', '')

  if v:shell_error == 0
    call s:Notify('✅ Backup completed', 'info')
  else
    call s:Notify('❌ Backup failed: ' . l:output, 'error')
  endif
endfunction

" Force backup now
function! backup#NowForce()
  call s:Notify('Forcing backup...', 'info')

  let l:output = s:ExecuteScript('backup-now.sh', '--force')

  if v:shell_error == 0
    call s:Notify('✅ Forced backup completed', 'info')
  else
    call s:Notify('❌ Backup failed: ' . l:output, 'error')
  endif
endfunction

" Restore from backup
function! backup#Restore()
  let l:bin_path = s:GetBinPath()
  if l:bin_path == ''
    return
  endif

  " Run in terminal
  if has('nvim')
    execute 'terminal ' . l:bin_path . '/backup-restore.sh'
  elseif has('terminal')
    execute 'terminal ' . l:bin_path . '/backup-restore.sh'
  else
    " Fallback to system
    execute '!' . l:bin_path . '/backup-restore.sh'
  endif
endfunction

" Cleanup preview
function! backup#Cleanup()
  let l:output = s:ExecuteScript('backup-cleanup.sh', '--preview')

  " Show in new split
  new
  setlocal buftype=nofile
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal nowrap

  call setline(1, split(l:output, "\n"))
  setlocal nomodifiable

  nnoremap <buffer> q :q<CR>
  nnoremap <buffer> <Esc> :q<CR>

  execute 'resize ' . min([line('$') + 1, 40])
endfunction

" Open backup config
function! backup#Config()
  let l:config_file = findfile('.backup-config.sh', '.;')

  if l:config_file != ''
    execute 'edit ' . l:config_file
  else
    echohl WarningMsg
    echo 'No .backup-config.sh found in current or parent directories'
    echohl None
  endif
endfunction

" ==============================================================================
" AUTO-TRIGGER
" ==============================================================================

function! backup#AutoTrigger()
  " Only trigger if enough time passed
  if !s:ShouldTrigger()
    return
  endif

  " Check if in git repository
  if !isdirectory('.git') && system('git rev-parse --git-dir') =~ 'fatal'
    return
  endif

  " Trigger in background (async if possible)
  if has('job')
    " Vim 8+ job
    let l:cmd = s:GetBinPath() . '/backup-now.sh --quiet'
    call job_start(l:cmd, {'in_mode': 'nl'})
  elseif has('nvim')
    " Neovim job
    let l:cmd = [s:GetBinPath() . '/backup-now.sh', '--quiet']
    call jobstart(l:cmd)
  else
    " Synchronous fallback
    call s:ExecuteScript('backup-now.sh', '--quiet &')
  endif
endfunction

" ==============================================================================
" STATUS LINE
" ==============================================================================

let s:status_cache = ''
let s:status_cache_time = 0

" Get status for statusline (cached)
function! backup#StatusLine()
  let l:now = localtime()

  " Update cache every 60 seconds
  if l:now - s:status_cache_time > 60
    let s:status_cache = backup#GetStatusCompact()
    let s:status_cache_time = l:now
  endif

  return s:status_cache
endfunction

" Get compact status
function! backup#GetStatusCompact()
  let l:bin_path = s:GetBinPath()
  if l:bin_path == ''
    return ''
  endif

  let l:script = l:bin_path . '/backup-status.sh'
  let l:output = system(shellescape(l:script) . ' --compact 2>/dev/null')

  if v:shell_error != 0
    return '❌'
  endif

  " Extract based on format
  if g:backup_statusline_format == 'emoji'
    " Just first emoji
    return matchstr(l:output, '^[✅⚠️❌]')
  elseif g:backup_statusline_format == 'compact'
    " Emoji + time
    let l:parts = split(l:output)
    return len(l:parts) >= 2 ? l:parts[0] . ' ' . l:parts[1] : l:output
  else
    " Full output
    return l:output
  endif
endfunction

" Initialize status line
function! backup#InitStatusLine()
  " Add to statusline if not already present
  if &statusline !~ 'BackupStatusLine'
    set statusline+=%{BackupStatusLine()}
  endif
endfunction

" Update status line (for timer)
function! backup#UpdateStatusLine(timer)
  " Force cache refresh
  let s:status_cache_time = 0
  redrawstatus
endfunction
