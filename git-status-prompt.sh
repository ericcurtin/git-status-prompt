#!/bin/bash

# git-status-prompt.sh - pretty format git sync and dirty status for shell prompt
# Copyright 2013-2017 bill-auger <http://github.com/bill-auger/git-status-prompt/issues>
# Copyright 2017      <-- YOUR_CONTACT_INFO_HERE -->
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


readonly DIRTY_CHAR="*"
readonly TRACKED_CHAR="!"
readonly UNTRACKED_CHAR="?"
readonly STAGED_CHAR="+"
readonly STASHED_CHAR="$"
readonly GIT_CLEAN_MSG_REGEX="nothing to commit,? (?working directory clean)?"

readonly GREEN='\e[0;32m'
readonly LIME='\e[1;32m'
readonly YELLOW='\e[1;33m'
readonly RED='\e[1;31m'
readonly NO_COLOR='\e[m'

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

HasAnyChanges() {
  if [[ $(git ls-files --o) ]]; then
    echo "$DIRTY_CHAR"
  fi
}

HasTrackedChanges() {
  if ! git diff --no-ext-diff --quiet --exit-code; then
    echo "$TRACKED_CHAR"
  fi
}

HasUntrackedChanges() {
  if [ -n "$(git ls-files --others --exclude-standard)" ]; then
    echo "$UNTRACKED_CHAR"
  fi
}

HasStagedChanges() {
  if ! git diff-index --cached --quiet HEAD --; then
    echo "$STAGED_CHAR"
  fi
}

HasStashedChanges() {
  if git rev-parse --verify refs/stash > /dev/null 2>&1; then
    echo "$STASHED_CHAR"
  fi
}

SyncStatus() {
  local_branch=$1 ; remote_branch=$2 ;
  status=`git rev-list --left-right ${local_branch}...${remote_branch} -- 2>/dev/null`

  if [ $(($?)) -eq 0 ]; then
    echo $status
  fi
}

GitStatus() {
  current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

  if [ "$?" -ne 0 ]; then
    return
  fi

  # detect detached HEAD state and abort
  if [ -f $PWD/.git/MERGE_HEAD ] &&
     [ ! -z "`cat .git/MERGE_MSG | /bin/grep '^Merge'`" ]; then
    merge_msg=`cat .git/MERGE_MSG | /bin/grep "^Merge (.*)(branch|tag|commit) '" | \
               sed -e "s/^Merge \(.*\)\(branch\|tag\|commit\) '\(.*\)'\( into .*\)\?$/ \3\4/"`
    echo "$UNTRACKED_COLOR(merging$merge_msg)$NO_COLOR"
    return
  elif [ -d $PWD/.git/rebase-apply/ ] || [ -d $PWD/.git/rebase-merge/ ]; then
    rebase_dir=`ls -d .git/rebase-* | sed -e "s/^.git\/rebase-\(.*\)$/.git\/rebase-\1/"`
    this_branch=`cat $rebase_dir/head-name | sed -e "s/^refs\/heads\/\(.*\)$/\1/"`
    their_commit=`cat $rebase_dir/onto`
    echo "$UNTRACKED_COLOR(rebasing $this_branch onto $their_commit)$NO_COLOR"
    return
  elif [ "$current_branch" == "HEAD" ]; then
    echo "$UNTRACKED_COLOR(detached)$NO_COLOR"
    return
  fi

  # loop over all branches to find remote tracking branch
  while read local_branch remote_branch; do
    # filter branches by name
    if [ "$current_branch" != "$local_branch" ]; then
      continue
    fi

    # set branch color based on dirty status
    if [ -z "$(HasAnyChanges)" ]; then
      branch_color=$CLEAN_COLOR
    else
      branch_color=$DIRTY_COLOR
    fi

    # get sync status
    if [ $remote_branch ]; then
      status=$(SyncStatus $local_branch $remote_branch)
      n_behind=`echo "$status" | tr " " "\n" | /bin/grep -c '^>'`
      n_ahead=` echo "$status" | tr " " "\n" | /bin/grep -c '^<'`

      # set sync color
      if [ "$n_behind" -ne 0 ]; then
        behind_color=$BEHIND_COLOR
      else
        behind_color=$EVEN_COLOR
      fi

      if [ "$n_ahead"  -ne 0 ]; then
        ahead_color=$AHEAD_COLOR
      else
        ahead_color=$EVEN_COLOR
      fi
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


    if [ $remote_branch ]; then
      behind_msg="$behind_color$n_behind<$NO_COLOR"
    fi

    if [ $remote_branch ]; then
      ahead_msg="$ahead_color>$n_ahead$NO_COLOR"
    fi

    if [ $remote_branch ]; then
      upstream_msg=$open_bracket$behind_msg$ahead_msg$close_bracket
    fi

    branch_status_msg=$NO_COLOR$branch_msg$status_msg$upstream_msg$NO_COLOR

    echo "$branch_status_msg"

  done < <(git for-each-ref --format="%(refname:short) %(upstream:short)" refs/heads)
}

GitStatusPrompt() {
  echo -e "$GREEN$(GitStatus)"
}
