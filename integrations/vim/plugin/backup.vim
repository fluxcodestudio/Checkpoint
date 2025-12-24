" Checkpoint - Vim/Neovim Plugin
" Version: 1.2.0
" Author: Jon Rezin
" License: MIT

" Prevent loading twice
if exists('g:loaded_backup_plugin')
  finish
endif
let g:loaded_backup_plugin = 1

" ==============================================================================
" CONFIGURATION
" ==============================================================================

" Enable/disable auto-trigger on save
if !exists('g:backup_auto_trigger')
  let g:backup_auto_trigger = 1
endif

" Auto-trigger delay (milliseconds)
if !exists('g:backup_trigger_delay')
  let g:backup_trigger_delay = 1000
endif

" Key mapping prefix
if !exists('g:backup_key_prefix')
  let g:backup_key_prefix = '<leader>'
endif

" Show notifications
if !exists('g:backup_notifications')
  let g:backup_notifications = 1
endif

" Path to backup bin directory
if !exists('g:backup_bin_path')
  " Try to auto-detect from environment
  let g:backup_bin_path = $CLAUDECODE_BACKUP_ROOT . '/bin'
  " Fallback
  if g:backup_bin_path == '/bin'
    let g:backup_bin_path = ''
  endif
endif

" Statusline format
if !exists('g:backup_statusline_format')
  let g:backup_statusline_format = 'compact'  " emoji, compact, verbose
endif

" ==============================================================================
" COMMANDS
" ==============================================================================

" Main backup commands
command! BackupStatus call backup#Status()
command! BackupNow call backup#Now()
command! BackupNowForce call backup#NowForce()
command! BackupRestore call backup#Restore()
command! BackupCleanup call backup#Cleanup()
command! BackupConfig call backup#Config()

" ==============================================================================
" KEY MAPPINGS
" ==============================================================================

if !exists('g:backup_no_mappings') || !g:backup_no_mappings
  " Status
  execute 'nnoremap ' . g:backup_key_prefix . 'bs :BackupStatus<CR>'

  " Backup now
  execute 'nnoremap ' . g:backup_key_prefix . 'bn :BackupNow<CR>'

  " Force backup
  execute 'nnoremap ' . g:backup_key_prefix . 'bf :BackupNowForce<CR>'

  " Restore
  execute 'nnoremap ' . g:backup_key_prefix . 'br :BackupRestore<CR>'

  " Cleanup
  execute 'nnoremap ' . g:backup_key_prefix . 'bc :BackupCleanup<CR>'

  " Config
  execute 'nnoremap ' . g:backup_key_prefix . 'bC :BackupConfig<CR>'
endif

" ==============================================================================
" AUTO-COMMANDS
" ==============================================================================

augroup backup_auto_trigger
  autocmd!

  " Auto-trigger on save (with debounce)
  if g:backup_auto_trigger
    autocmd BufWritePost * call backup#AutoTrigger()
  endif

  " Update statusline periodically
  if has('timers')
    " Update every 60 seconds
    call timer_start(60000, 'backup#UpdateStatusLine', {'repeat': -1})
  endif
augroup END

" ==============================================================================
" STATUS LINE INTEGRATION
" ==============================================================================

" Function to get backup status for statusline
function! BackupStatusLine()
  return backup#StatusLine()
endfunction

" Initialize status line
call backup#InitStatusLine()
