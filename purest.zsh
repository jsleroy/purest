# Pure
# by Sindre Sorhus
# https://github.com/sindresorhus/pure
# MIT License

# For my own and others sanity
# git:
# %b => current branch
# %a => current action (rebase/merge)
# prompt:
# %F => color dict
# %f => reset color
# %~ => current path
# %* => time
# %n => username
# %m => shortname host
# %(?..) => prompt conditional - %(condition.true.false)
# terminal codes:
# \e7   => save cursor position
# \e[2A => move cursor 2 lines up
# \e[1G => go to position 1 in terminal
# \e8   => restore cursor position
# \e[K  => clears everything after the cursor on the current line
# \e[2K => clear everything on the current line

PURER_PROMPT_COMMAND_COUNT=0
STATUS_COLOR='blue'

# turns seconds into human readable time
# 165392 => 1d 21h 56m 32s
# https://github.com/sindresorhus/pretty-time-zsh
prompt_pure_human_time_to_var() {
  local human=" [" total_seconds=$1 var=$2
  local days=$(( total_seconds / 60 / 60 / 24 ))
  local hours=$(( total_seconds / 60 / 60 % 24 ))
  local minutes=$(( total_seconds / 60 % 60 ))
  local seconds=$(( total_seconds % 60 ))
  (( days > 0 )) && human+="${days}d "
  (( hours > 0 )) && human+="${hours}h "
  (( minutes > 0 )) && human+="${minutes}m "
  human+="${seconds}s]"

  # store human readable time in variable as specified by caller
  typeset -g "${var}"="${human}"
}

# stores (into prompt_pure_cmd_exec_time) the exec time of the last command if set threshold was exceeded
prompt_pure_check_cmd_exec_time() {
  integer elapsed
  (( elapsed = EPOCHSECONDS - ${prompt_pure_cmd_timestamp:-$EPOCHSECONDS} ))
  prompt_pure_cmd_exec_time=
  (( elapsed > ${PURE_CMD_MAX_EXEC_TIME:=5} )) && {
  prompt_pure_human_time_to_var $elapsed "prompt_pure_cmd_exec_time"
}
}

prompt_pure_clear_screen() {
  # enable output to terminal
  zle -I
  # clear screen and move cursor to (0, 0)
  print -n '\e[2J\e[0;0H'
  # reset command count to zero so we don't start with a blank line
  PURER_PROMPT_COMMAND_COUNT=0
  # print preprompt
  prompt_pure_preprompt_render precmd
}

# set STATUS_COLOR: blue for "insert", purple for "normal" mode.
prompt_purer_vim_mode() {
  STATUS_COLOR="${${KEYMAP/vicmd/202}/(main|viins)/blue}"
  prompt_pure_preprompt_render
}

prompt_pure_set_title() {
  # emacs terminal does not support settings the title
  (( ${+EMACS} )) && return

  # tell the terminal we are setting the title
  print -n '\e]0;'
  # show hostname if connected through ssh
  [[ -n $SSH_CONNECTION ]] && print -Pn '(%m) '
  case $1 in
    expand-prompt)
      print -Pn $2;;
    ignore-escape)
      print -rn $2;;
  esac
  # end set title
  print -n '\a'
}

prompt_pure_preexec() {
  # attempt to detect and prevent prompt_pure_async_git_fetch from interfering with user initiated git or hub fetch
  [[ $2 =~ (git|hub)\ .*(pull|fetch) ]] && async_flush_jobs 'prompt_pure'

  prompt_pure_cmd_timestamp=$EPOCHSECONDS

  # shows the current dir and executed command in the title while a process is active
  prompt_pure_set_title 'ignore-escape' "$PWD:t: $2"
}

# string length ignoring ansi escapes
prompt_pure_string_length_to_var() {
  local str=$1 var=$2 length
  # perform expansion on str and check length
  length=$(( ${#${(S%%)str//(\%([KF1]|)\{*\}|\%[Bbkf])}} ))

  # store string length in variable as specified by caller
  typeset -g "${var}"="${length}"
}

prompt_pure_preprompt_render() {
  # store the current prompt_subst setting so that it can be restored later
  local prompt_subst_status=$options[prompt_subst]

  # make sure prompt_subst is unset to prevent parameter expansion in preprompt
  setopt local_options no_prompt_subst

  # check that no command is currently running, the preprompt will otherwise be rendered in the wrong place
  [[ -n ${prompt_pure_cmd_timestamp+x} && "$1" != "precmd" ]] && return

  # set color for git branch/dirty status, change color if dirty checking has been delayed
  local git_color=242
  [[ -n ${prompt_pure_git_last_dirty_check_timestamp+x} ]] && git_color=red

  # construct preprompt
  local preprompt=""


  # add a newline between commands
  FIRST_COMMAND_THRESHOLD=1
  if [[ "$PURER_PROMPT_COMMAND_COUNT" -gt "$FIRST_COMMAND_THRESHOLD" ]]; then
    # preprompt+=$'\n'
    preprompt+=$''
  fi

  local symbol_color="%(?.${PURE_PROMPT_SYMBOL_COLOR:-green}.red)"

  # directory, colored by vim status
  preprompt+="%B%F{$STATUS_COLOR}${PUREST_PATH_EXPANSION:-%c}%f%b"
  # git info
  preprompt+="%F{$git_color}${vcs_info_msg_0_}${prompt_pure_git_dirty}%f"
  # git pull/push arrows
  preprompt+="%F{blue}${prompt_pure_git_arrows}%f"
  # username and machine if applicable
  preprompt+=$prompt_pure_username
  # execution time
  preprompt+="%B%F{242}${prompt_pure_cmd_exec_time}%f%b"

  preprompt+=" "

  # end with symbol, colored by previous command exit code
  preprompt+="%F{$symbol_color}${PURE_PROMPT_SYMBOL:-❯}%f"

  preprompt+=" "

  # make sure prompt_pure_last_preprompt is a global array
  typeset -g -a prompt_pure_last_preprompt

  PROMPT="$preprompt"

  # if executing through precmd, do not perform fancy terminal editing
  if [[ "$1" != "precmd" ]]; then
    # only redraw if the expanded preprompt has changed
    # [[ "${prompt_pure_last_preprompt[2]}" != "${(S%%)preprompt}" ]] || return

    # redraw prompt (also resets cursor position)
    zle && zle .reset-prompt

    setopt no_prompt_subst
  fi

  # store both unexpanded and expanded preprompt for comparison
  prompt_pure_last_preprompt=("$preprompt" "${(S%%)preprompt}")
}

prompt_pure_precmd() {
  # check exec time and store it in a variable
  prompt_pure_check_cmd_exec_time

  # by making sure that prompt_pure_cmd_timestamp is defined here the async functions are prevented from interfering
  # with the initial preprompt rendering
  prompt_pure_cmd_timestamp=

  # shows the full path in the title
  prompt_pure_set_title 'expand-prompt' '%~'

  # get vcs info
  vcs_info

  # preform async git dirty check and fetch
  prompt_pure_async_tasks

  # Increment command counter
  PURER_PROMPT_COMMAND_COUNT=$((PURER_PROMPT_COMMAND_COUNT+1))

  # print the preprompt
  prompt_pure_preprompt_render "precmd"

  # remove the prompt_pure_cmd_timestamp, indicating that precmd has completed
  unset prompt_pure_cmd_timestamp
}

# fastest possible way to check if repo is dirty
prompt_pure_async_git_dirty() {
  setopt localoptions noshwordsplit
  local untracked_dirty=$1 dir=$2

  # use cd -q to avoid side effects of changing directory, e.g. chpwd hooks
  builtin cd -q $dir

  if [[ $untracked_dirty = 0 ]]; then
    command git diff --no-ext-diff --quiet --exit-code
  else
    test -z "$(command git status --porcelain --ignore-submodules -unormal)"
  fi

  return $?
}

prompt_pure_async_git_fetch() {
  setopt localoptions noshwordsplit
  # use cd -q to avoid side effects of changing directory, e.g. chpwd hooks
  builtin cd -q $1

  # set GIT_TERMINAL_PROMPT=0 to disable auth prompting for git fetch (git 2.3+)
  export GIT_TERMINAL_PROMPT=0
  # set ssh BachMode to disable all interactive ssh password prompting
  export GIT_SSH_COMMAND=${GIT_SSH_COMMAND:-"ssh -o BatchMode=yes"}

  command git -c gc.auto=0 fetch &>/dev/null || return 1

  # check arrow status after a successful git fetch
  prompt_pure_async_git_arrows $1
}

prompt_pure_async_git_arrows() {
  setopt localoptions noshwordsplit
  builtin cd -q $1
  command git rev-list --left-right --count HEAD...@'{u}'
}

prompt_pure_async_tasks() {
  setopt localoptions noshwordsplit

  # initialize async worker
  ((!${prompt_pure_async_init:-0})) && {
  async_start_worker "prompt_pure" -u -n
  async_register_callback "prompt_pure" prompt_pure_async_callback
  prompt_pure_async_init=1
}

# store working_tree without the "x" prefix
local working_tree="${vcs_info_msg_1_#x}"

# check if the working tree changed (prompt_pure_current_working_tree is prefixed by "x")
if [[ ${prompt_pure_current_working_tree#x} != $working_tree ]]; then
  # stop any running async jobs
  async_flush_jobs "prompt_pure"

  # reset git preprompt variables, switching working tree
  unset prompt_pure_git_dirty
  unset prompt_pure_git_last_dirty_check_timestamp
  prompt_pure_git_arrows=

  # set the new working tree and prefix with "x" to prevent the creation of a named path by AUTO_NAME_DIRS
  prompt_pure_current_working_tree="x${working_tree}"
fi

# only perform tasks inside git working tree
[[ -n $working_tree ]] || return

async_job "prompt_pure" prompt_pure_async_git_arrows $working_tree

# do not preform git fetch if it is disabled or working_tree == HOME
if (( ${PURE_GIT_PULL:-1} )) && [[ $working_tree != $HOME ]]; then
  # tell worker to do a git fetch
  async_job "prompt_pure" prompt_pure_async_git_fetch $working_tree
fi

# if dirty checking is sufficiently fast, tell worker to check it again, or wait for timeout
integer time_since_last_dirty_check=$(( EPOCHSECONDS - ${prompt_pure_git_last_dirty_check_timestamp:-0} ))
if (( time_since_last_dirty_check > ${PURE_GIT_DELAY_DIRTY_CHECK:-1800} )); then
  unset prompt_pure_git_last_dirty_check_timestamp
  # check check if there is anything to pull
  async_job "prompt_pure" prompt_pure_async_git_dirty ${PURE_GIT_UNTRACKED_DIRTY:-1} $working_tree
fi
}

prompt_pure_check_git_arrows() {
  setopt localoptions noshwordsplit
  local arrows left=${1:-0} right=${2:-0}

  (( right > 0 )) && arrows+=${PURE_GIT_DOWN_ARROW:-⇣}
  (( left > 0 )) && arrows+=${PURE_GIT_UP_ARROW:-⇡}

  [[ -n $arrows ]] || return
  typeset -g REPLY=" $arrows"
}

prompt_pure_async_callback() {
  setopt localoptions noshwordsplit
  local job=$1 code=$2 output=$3 exec_time=$4

  case $job in
    prompt_pure_async_git_dirty)
      local prev_dirty=$prompt_pure_git_dirty
      if (( code == 0 )); then
        prompt_pure_git_dirty=
      else
        prompt_pure_git_dirty="*"
      fi

      [[ $prev_dirty != $prompt_pure_git_dirty ]] && prompt_pure_preprompt_render

      # When prompt_pure_git_last_dirty_check_timestamp is set, the git info is displayed in a different color.
      # To distinguish between a "fresh" and a "cached" result, the preprompt is rendered before setting this
      # variable. Thus, only upon next rendering of the preprompt will the result appear in a different color.
      (( $exec_time > 2 )) && prompt_pure_git_last_dirty_check_timestamp=$EPOCHSECONDS
      ;;
    prompt_pure_async_git_fetch|prompt_pure_async_git_arrows)
      # prompt_pure_async_git_fetch executes prompt_pure_async_git_arrows
      # after a successful fetch.
      if (( code == 0 )); then
        local REPLY
        prompt_pure_check_git_arrows ${(ps:\t:)output}
        if [[ $prompt_pure_git_arrows != $REPLY ]]; then
          prompt_pure_git_arrows=$REPLY
          prompt_pure_preprompt_render
        fi
      fi
      ;;
  esac
}

prompt_pure_setup() {
  # prevent percentage showing up
  # if output doesn't end with a newline
  export PROMPT_EOL_MARK=''

  # prompt_opts=(subst percent)

  # borrowed from promptinit, sets the prompt options in case pure was not
  # initialized via promptinit.
  # setopt noprompt{bang,cr,percent,subst} "prompt${^prompt_opts[@]}"

  zmodload zsh/datetime
  zmodload zsh/zle
  zmodload zsh/parameter

  autoload -Uz add-zsh-hook
  autoload -Uz vcs_info
  autoload -Uz async && async

  add-zsh-hook precmd prompt_pure_precmd
  add-zsh-hook preexec prompt_pure_preexec

  zstyle ':vcs_info:*' enable git
  zstyle ':vcs_info:*' use-simple true
  # only export two msg variables from vcs_info
  zstyle ':vcs_info:*' max-exports 2
  # vcs_info_msg_0_ = ' %b' (for branch)
  # vcs_info_msg_1_ = 'x%R' git top level (%R), x-prefix prevents creation of a named path (AUTO_NAME_DIRS)
  zstyle ':vcs_info:git*' formats ' %b' 'x%R'
  zstyle ':vcs_info:git*' actionformats ' %b|%a' 'x%R'

  # if the user has not registered a custom zle widget for clear-screen,
  # override the builtin one so that the preprompt is displayed correctly when
  # ^L is issued.
  if [[ $widgets[clear-screen] == 'builtin' ]]; then
    zle -N clear-screen prompt_pure_clear_screen
  fi

  # register custom function for vim-mode
  zle -N zle-keymap-select prompt_purer_vim_mode

  # show username@host if logged in through SSH
  [[ "$SSH_CONNECTION" != '' ]] && prompt_pure_username=' %F{242}%n@%m%f'

  # show username@host if root, with username in white
  [[ $UID -eq 0 ]] && prompt_pure_username=' %F{white}%n%f%F{242}@%m%f'

  # show hostname override if it exists
  [[ "$PURER_HOSTNAME_OVERRIDE" != '' ]] && prompt_pure_username=' %F{white}'"$PURER_HOSTNAME_OVERRIDE"

  # create prompt
  prompt_pure_preprompt_render 'precmd'
}

prompt_pure_setup "$@"
