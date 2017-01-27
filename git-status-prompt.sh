#!/bin/bash

# git-status-prompt.sh
# Copyright 2013-2016 bill-auger <http://github.com/bill-auger/git-status-prompt/issues>

# this script formats git branch name plus dirty and sync status for appending to bash prompt
# format is: (branch-name status-indicators [divergence]) last-commit-message
#   '*' character indicates that the working tree differs from HEAD
#   '!' character indicates that some tracked files have changed
#   '?' character indicates that some new or untracked files exist
#   '+' character indicates that some changes are staged for commit
#   '$' character indicates that a stash exists
#   [n<-->n] indicates the number of commits behind and ahead of upstream
# usage:
#   source ~/bin/git-status-prompt/git-status-prompt.sh
#   PS1="\$(GitStatusPrompt)"

readonly GREEN='\e[0;32m'
readonly NO_COLOR='\e[m'

readonly DIRTY_CHAR="*"
readonly TRACKED_CHAR="!"
readonly UNTRACKED_CHAR="?"
readonly STAGED_CHAR="+"
readonly STASHED_CHAR="$"
readonly GIT_CLEAN_MSG_REGEX="nothing to commit,? (?working directory clean)?"
readonly LIME='\e[1;32m'
readonly YELLOW='\e[1;33m'
readonly RED='\e[1;31m'
readonly CLEAN_COLOR=$GREEN
readonly DIRTY_COLOR=$YELLOW
readonly TRACKED_COLOR=$YELLOW
readonly UNTRACKED_COLOR=$RED
readonly STAGED_COLOR=$GREEN
readonly STASHED_COLOR=$LIME
readonly BEHIND_COLOR=$RED
readonly AHEAD_COLOR=$YELLOW
readonly EVEN_COLOR=$GREEN
readonly ANSI_FILTER_REGEX="s/\\\033\[([0-9]{1,2}(;[0-9]{1,2})?)?m//g"
readonly TIMESTAMP_LEN=10


# helpers

function AssertIsValidRepo
{
  git rev-parse --is-inside-work-tree > /dev/null 2>&1 && echo "OK"
}

function AssertHasCommits
{
  # TODO: does this fail if detached HEAD ?
  git cat-file -t HEAD > /dev/null 2>&1 && echo "OK"
}

function HasAnyChanges
{
  [ "`git status 2> /dev/null | tail -n1 | /bin/grep \"$GIT_CLEAN_MSG_REGEX\"`" ] || echo "$DIRTY_CHAR"
}

function HasTrackedChanges
{
  git diff --no-ext-diff --quiet --exit-code || echo "$TRACKED_CHAR"
}

function HasUntrackedChanges
{
  [ -n "$(git ls-files --others --exclude-standard)" ] && echo "$UNTRACKED_CHAR"
}

function HasStagedChanges
{
  git diff-index --cached --quiet HEAD -- || echo "$STAGED_CHAR"
}

function HasStashedChanges
{
  git rev-parse --verify refs/stash > /dev/null 2>&1 && echo "$STASHED_CHAR"
}

function SyncStatus
{
  local_branch=$1 ; remote_branch=$2 ;
  status=`git rev-list --left-right ${local_branch}...${remote_branch} -- 2>/dev/null`
  [ $(($?)) -eq 0 ] && echo $status
}

function GitStatus
{
  # ensure we are in a valid git repository with commits
  [ ! $(AssertIsValidRepo) ]                        && return
  [ ! $(AssertHasCommits)  ] && echo "(no commits)" && return

  current_branch=`git rev-parse --abbrev-ref HEAD` ; [ $current_branch ] || return ;

  # detect detached HEAD state and abort
  if   [ -f $PWD/.git/MERGE_HEAD ] && [ ! -z "`cat .git/MERGE_MSG | /bin/grep '^Merge'`" ]
  then merge_msg=`cat .git/MERGE_MSG | /bin/grep "^Merge (.*)(branch|tag|commit) '"               | \
                  sed -e "s/^Merge \(.*\)\(branch\|tag\|commit\) '\(.*\)'\( into .*\)\?$/ \3\4/"`
       echo "$UNTRACKED_COLOR(merging$merge_msg)$NO_COLOR"  ; return ;
  elif [ -d $PWD/.git/rebase-apply/ ] || [ -d $PWD/.git/rebase-merge/ ]
  then rebase_dir=`ls -d .git/rebase-* | sed -e "s/^.git\/rebase-\(.*\)$/.git\/rebase-\1/"`
       this_branch=`cat $rebase_dir/head-name | sed -e "s/^refs\/heads\/\(.*\)$/\1/"`
       their_commit=`cat $rebase_dir/onto`
       echo "$UNTRACKED_COLOR(rebasing $this_branch onto $their_commit)$NO_COLOR" ; return ;
  elif [ "$current_branch" == "HEAD" ]
  then echo "$UNTRACKED_COLOR(detached)$NO_COLOR" ; return ;
  fi

  # loop over all branches to find remote tracking branch
  while read local_branch remote_branch
  do
    # filter branches by name
    [ "$current_branch" != "$local_branch" ] && continue

    # set branch color based on dirty status
    if [ -z "$(HasAnyChanges)" ] ; then branch_color=$CLEAN_COLOR ; else branch_color=$DIRTY_COLOR ; fi ;

    # get sync status
    if [ $remote_branch ] ; then
      status=$(SyncStatus $local_branch $remote_branch)
      n_behind=`echo "$status" | tr " " "\n" | /bin/grep -c '^>'`
      n_ahead=` echo "$status" | tr " " "\n" | /bin/grep -c '^<'`

      # set sync color
      if [ "$n_behind" -ne 0 ] ; then behind_color=$BEHIND_COLOR ; else behind_color=$EVEN_COLOR ; fi ;
      if [ "$n_ahead"  -ne 0 ] ; then ahead_color=$AHEAD_COLOR ;   else ahead_color=$EVEN_COLOR ;  fi ;
    fi

    # get tracked status
    tracked=$(HasTrackedChanges)

    # get untracked status
    untracked=$(HasUntrackedChanges)

    # get staged status
    staged=$(HasStagedChanges)

    # get stashed status
    stashed=$(HasStashedChanges)

    # build output
    open_paren="$branch_color($NO_COLOR"
    close_paren="$branch_color)$NO_COLOR"
    open_bracket="$branch_color$NO_COLOR"
    close_bracket="$branch_color$NO_COLOR"
    tracked_msg=$TRACKED_COLOR$tracked$NO_COLOR
    untracked_msg=$UNTRACKED_COLOR$untracked$NO_COLOR
    staged_msg=$STAGED_COLOR$staged$NO_COLOR
    stashed_msg=$STASHED_COLOR$stashed$NO_COLOR
    branch_msg=$branch_color$current_branch$NO_COLOR
    status_msg=$stashed_msg$untracked_msg$tracked_msg$staged_msg
    [ $remote_branch ] && behind_msg="$behind_color$n_behind<$NO_COLOR"
    [ $remote_branch ] && ahead_msg="$ahead_color>$n_ahead$NO_COLOR"
    [ $remote_branch ] && upstream_msg=$open_bracket$behind_msg$ahead_msg$close_bracket
    branch_status_msg=$NO_COLOR$branch_msg$status_msg$upstream_msg$NO_COLOR

    echo "$branch_status_msg"

  done < <(git for-each-ref --format="%(refname:short) %(upstream:short)" refs/heads)
}


# main entry point

function GitStatusPrompt
{
  echo -e "$GREEN$(GitStatus)"
}
