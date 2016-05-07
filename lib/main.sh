#!/bin/sh

# Main entry point and command handler
#
# Author: arctelix
#
# Thanks to the following sources:
# https://github.com/agross/dotfiles
# https://github.com/holman/dotfiles
# https://github.com/webpro/dotfiles
#
# Other useful reference
# http://superuser.com/questions/789448/choosing-between-bashrc-profile-bash-profile-etc
#
# Licence: The MIT License (MIT)
# Copyright (c) 2016 Arctelix https://github.com/arctelix
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation
# files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,
# modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
# BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF
# OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.



#TODO: Append *.stub to git ignore for every repo
#TODO: TEST new repo branch syntax = "action user/repo:branch" or "action repo branch"
#TODO: change .dotsys.cfg to dotsys.cfg so we can hide them with a .

#TODO: handle .settings files
#TODO: FOR NEW Installs prompt for --force & --confirm options
#TODO: Finish implementing func_or_func_msg....
#TODO: Detect platforms like babun and mysys as separate configs, and allow user to specify system.
#TODO: Create option to delete unused topics from non primary repos from user's .dotfies .directory after install

#TODO QUESTION: Change "freeze" to "show".. as in show status.  ie show brew, show git, show tmux?
#TODO QUESTION: Symlink "(o)ption all" choices should apply to all topics? (currently just for current topic)?
#TODO QUESTION: Hold manager's packages install to end of topic run?
#TODO QUESTION: Currently repo holds user files, maybe installed topics should be copied to internal user directory.
# - Currently changes to dotfiles do not require a dotsys update since they are symlinked, the change would require this.
# - Currently if a repo is deleted the data is gone, the change would protect topics in use.



# Fail on errors.
# set -e

# Show executed commands
#set -x

# Dotsys debug system true/false
DEBUG=false

if ! [ "$DOTSYS_LIBRARY" ];then
    if [ ! -f "$0" ];then
        DOTSYS_REPOSITORY="$(dirname "$BASH_SOURCE")"
    else
        DOTSYS_REPOSITORY="$(dirname "$0")"
    fi
    DOTSYS_LIBRARY="$DOTSYS_REPOSITORY/lib"
fi

#echo "main DOTSYS_LIBRARY: $DOTSYS_LIBRARY"
. "$DOTSYS_LIBRARY/common.sh"
. "$DOTSYS_LIBRARY/yaml.sh"
. "$DOTSYS_LIBRARY/terminalio.sh"
. "$DOTSYS_LIBRARY/state.sh"
. "$DOTSYS_LIBRARY/iterators.sh"
. "$DOTSYS_LIBRARY/platforms.sh"
. "$DOTSYS_LIBRARY/scripts.sh"
. "$DOTSYS_LIBRARY/managers.sh"
. "$DOTSYS_LIBRARY/symlinks.sh"
. "$DOTSYS_LIBRARY/config.sh"
. "$DOTSYS_LIBRARY/repos.sh"
. "$DOTSYS_LIBRARY/stubs.sh"


#GLOBALS
STATE_SYSTEM_KEYS="installed_repo"
DEFAULT_APP_MANAGER=
DEFAULT_CMD_MANAGER=

# current active repo (set by load_config_vars)
ACTIVE_REPO=
ACTIVE_REPO_DIR=

# user info (set by set_user_vars)
PRIMARY_REPO=
USER_NAME=
REPO_NAME=

# persist state for topic actions & symlinks
GLOBAL_CONFIRMED=

# persist state for topic actions only
TOPIC_CONFIRMED=

# Default dry run state is off
# use 'dry_run 0' to toggle on
# use 'if dry_run' to test for state
DRY_RUN_STATE=1
# Default dry run message is back space
DRY_RUN="\b"

# track mangers actively used by topics or packages
ACTIVE_MANAGERS=()

# track uninstalled topics (populated but not used)
UNINSTALLED_TOPICS=()

# track installed topics (populated but not used)
INSTALLED=()

# Current platform
PLATFORM="$(get_platform)"

# path to platform's system user bin
PLATFORM_USER_BIN="$(platform_user_bin)"

# path to debug file
DEBUG_FILE="$DOTSYS_REPOSITORY/debug.log"

# Determines if logo,stats,and other verbose messages are shownm
VERBOSE_MODE=

#debug "DOTFILES_ROOT: $(dotfiles_dir)"

dotsys () {
    local usage="dotsys <action> [<topics> <limits> <options>]"
    local usage_full="
    <action> required:  Primary action to take on one or more topics.

    install         runs install scripts, downloads repos,
                    and installs package_manager packages
    uninstall       runs uninstall scripts deletes repos,
                    and uninstalls package_manager packages
    upgrade         runs upgrade scripts, upgrades packages,
                    and sync remote repos
    update          runs update scripts, update package managers
                    re-sources bin, re-sources stubs
    freeze [<mode>] creates config file of current state, takes optional mode <default,user,topic,full>

    <topics> optional:

    Limits action to specified topics (space separated list)
    Omit topic for all all available topics

    <limits> optional:

    -d | dotsys             Limit action to dotsys (excludes package management)
    -r | repo [branch]      Limit action to primary repo management (not topics)
    <user/repo[:branch]>    Same as 'repo' for specified repo
    -l | links              Limit action to symlinks
    -m | managers           Limit action to package managers
    -s | scripts            Limit action to scripts
    -f | from <user/repo>   Apply action to topics from specified repo
    -p | packages           Limit action to package manager's packages
    -c | cmd                Limit action to cmd manager's packages
    -a | app                Limit action to app manager's packages

    <options> optional: use to bypass confirmations.
    --force             force action even if already completed
    --tlogo             Toggle logo for this run only
    --tstats            Toggle stats for this run only
    --debug             Debug mode on
    --dryrun            Runs through all tasks, but no changes are actually made (must confirm each task)
    --confirm           bypass topic confirmation and backup / restore backup for existing symlinks
    --confirm delete    bypass topic confirmation and delete existing symlinks on install & uninstall
    --confirm backup    bypass topic confirmation and backup existing symlinks on install & restore backups on uninstall
    --confirm dryrun    Same as dryrun option but bypasses confirmations


    Example usage:

    - Install all topics
      $ dotsys install
    - Uninstall one or more topics
      $ dotsys uninstall vim tmux
    - Upgrade one or more topics and bypass confirmation (symlinks will need to be confirmed)
      $ dotsys upgrade brew dotsys --confirm delete
    - Upgrade one or more topics and bypass confirmation (symlinks will need to be confirmed)
      $ dotsys upgrade brew dotsys --confirm backup
    - Install a manager package without a topic
      $ dotsys install brew packages google-chrome
    - Install a command line util without a topic using default manager
      $ dotsys install cmd git
    - Install an os app without a topic using default manager
      $ dotsys install app google-chrome


    Organization:       NOTE: Any file or directory prefixed with a "." will be ignored by dotsys


      repos:            .dotfiels/user_name/repo_name
                        A repo contains a set of topics and correlates to a github repository
                        You can install topics from as many repos as you like.

      symlinks:         topic/*.symlink
                        Symlinked to home or specified directory


      bins:             topic/bin
                        All files inside a topic bin will be available
                        on the command line by simlinking to dotsys/bin

      managers:         topic/manager.sh
                        Manages packages of some type, such as brew,
                        pip, npm, etc.. (see script manager.sh for details)

      configs:          Configs are yaml like configuration files that tell
                        dotsys how to handle a repo and or topics.  You can
                        customize almost everything about a repo and topic
                        behavior with .dotsys.cfg file.
                        repo/dotsys.cfg repo level config file
                        topic/dotsys.cfg topic level config file

      stubs:            topic/file.stub
                        Stubs allow topics to collect user information and to add
                        functionality to each other. For example: The stub for
                        .vimrc is symlinked to your $HOME
                        directory where vim will read it.  The stub will then source
                        your vim/vimrc.symlink and search for other topic/*.vim files.

    scripts:            scripts are optional and placed in each topic root directory

      topic/topic.sh    A single script containing optional functions for each required
                        action (see function definitions)

      topic/manager.sh  Designates a topic as a manager. Functions handle packages not the manager!
                        Required functions for installing packages: install, uninstall, upgrade
                        Not supported: update & freeze as these are in the manager topic.sh file.

      script functions: The rules below are important (please follow them strictly)

        install:          Makes permanent changes that only require running on initial install (run once)!

        uninstall         Must undo everything done by install (run once)!

        upgrade           Only use for changes that bump the installed component version!
                          Topics with a manager typically wont need this, the manager will handle it.

        update:           Only use to update dotsys with local changes or data (DO NOT BUMP VERSIONS)!
                          ex: reload a local config file so changes are available in the current session
                          ex: refresh data from a webservice

        freeze:           Output the current state of the topic
                          ex: A manager would list installed topics
                          ex: git will show the current status

    depreciated scripts:use topic.sh functions
      install.sh        see action function definitions
      uninstall.sh      see action function definitions
      upgrade.sh        see action function definitions
      update.sh         see action function definitions
    "

    check_for_help "$1"

    local action=
    local freeze_mode=

    case $1 in
        install )   action="install" ;;
        uninstall)  action="uninstall" ;;
        upgrade )   action="upgrade" ;;
        update )    action="update" ;;
        freeze)     action="freeze"
                    if [[ "$FREEZE_MODES" =~ "$2" ]];then
                        freeze_mode="$2"
                        shift
                    fi ;;
        * )  error "Invalid action: $1 %b"
           show_usage ;;
    esac
    shift

    local topics=()
    local limits=()
    local force=
    local from_repo=
    local from_branch=
    # allow toggle on a per run basis
    # also used internally to limit to one showing
    # use user_toggle_logo to turn logo off permanently
    local show_logo=0
    local show_stats=0

    while [[ $# > 0 ]]; do
    case $1 in
        # limits
        -d | dotsys )   limits+=("dotsys") ;;
        -r | repo)      limits+=("repo")    #no topics permitted (just branch)
                        if [ "$2" ] && [[ "$2" != "-"* ]]; then from_branch="$2";shift ;fi ;;
        -l | links)     limits+=("links") ;;
        -m | managers)  limits+=("managers") ;;
        -s | scripts)   limits+=("scripts") ;;
        -f | from)      from_repo="$2"; shift ;;
        -p | packages)  limits+=("packages") ;;
        -a | app)       limits+=("packages") ;;
        -c | cmd)       limits+=("packages") ;;

        # options
        --force)        force="$1" ;;
        --tlogo)        ! get_state_value "show_logo"; show_logo=$? ;;
        --tstats)       ! get_state_value "show_stats"; show_stats=$? ;;
        --debug)        DEBUG="true" ;;
        --recursive)    recursive="true" ;; # used internally for recursive calls
        --dryrun)       dry_run 0 ;;
        --confirm)      if [[ "$2" =~ (delete|backup|skip) ]]; then
                            GLOBAL_CONFIRMED="$2"
                            if [ "$2" = "dryrun" ]; then
                                dry_run 0
                                GLOBAL_CONFIRMED="skip"
                            fi
                            shift
                        # default val for confirm
                        else
                            GLOBAL_CONFIRMED="backup"
                        fi ;;
        --*)            invalid_option ;;
        -*)             invalid_limit ;;
        *)              topics+=("$1") ;;
    esac
    shift
    done

    required_vars "action"

    debug "[ START DOTSYS ]-> a:$action t:${topics[@]} l:$limits force:$force conf:$GLOBAL_CONFIRMED r:$recursive from:$from_repo"

    # SET VERBOSE_MODE
    verbose_mode

    # SET CONFIRMATIONS

    # bypass confirmations when topics provided
    if [ "${topics[0]}" ] || [[ "$action" =~ (update|upgrade|freeze) ]]; then
        debug "main -> Set GLOBAL_CONFIRMED = backup (Topics specified or not install/uninstall)"
        GLOBAL_CONFIRMED="backup"
    fi

    # override for dryrun option
    if dry_run; then
        GLOBAL_CONFIRMED="skip"
    fi

    TOPIC_CONFIRMED="${TOPIC_CONFIRMED:-$GLOBAL_CONFIRMED}"

    # DIRECT MANGER PACKAGE MANAGEMENT
    # This allows dotsys to manage packages without a topic directory
    # <manager> may be 'cmd' 'app' or specific manager name
    # for example: 'dotsys install <manager> packages <packages>'   # specified packages
    # for example: 'dotsys install <manager> packages file'         # all packages in package file
    # for example: 'dotsys install <manager> packages'              # all installed packages
    # todo: Consider api format 'dotsys <manager> install <package>'
    if in_limits "packages" -r && is_manager "${topics[0]}" && [ ${#topics[@]} -gt 1 ] ; then
      local manager="$(get_default_manager "${topics[0]}")" # checks for app or cmd
      local i=0 # just to make my syntax checker not fail (weird)
      unset topics[$i]
      debug "main -> ONLY $action $manager ${limits[@]} ${topics[@]} $force"
      manage_packages "$action" "$manager" ${topics[@]} "$force"
      return
    fi

    # HANDLE REPO LIMIT

    # First topic "repo" or "xx/xx" is equivalent to setting limits="repo"
    if topic_is_repo; then
        debug "main -> topic is repo: ${topics[0]}"
        limits+=("repo")
        from_repo="${topics[0]}"
        topics=

    # allows syntax action "repo"
    elif [ ! "$from_repo" ] && in_limits "repo" -r; then
        debug "main -> repo is in limits"
        from_repo="repo"
        topics=
    fi

    # allow "repo" as shortcut to active repo
    if [ "$from_repo" = "repo" ] ; then
        from_repo="$(get_active_repo)"
        if ! [ "$from_repo" ]; then
            error "There is no primary repo configured, so
            $spacer a repo must be explicitly specified"
            exit
        fi

    fi

    # LOAD CONFIG VARS Parses from_repo, Loads config file, manages repo
    if ! [ "$recursive" ]; then
        debug "main -> load config vars"
        if [ "$from_branch" ]; then
            debug "   got from_branch: $from_branch"
            from_repo="${from_repo}:$from_branch"
            debug "   new from_repo = $from_repo"
        fi
        load_config_vars "$from_repo" "$action"
    fi

    # FREEZE installed topics or create config yaml
    if [ "$action" = "freeze" ] && in_limits "dotsys"; then
        debug "main -> freeze_mode: $freeze_mode"
        if in_limits -r "repo"; then
            create_config_yaml "$ACTIVE_REPO" "${limits[@]}"
            return
        else
            freeze "$ACTIVE_REPO" "${limits[@]}"
        fi
    fi

    # END REPO LIMIT if repo in limits dotsys has ended
    if in_limits -r "repo"; then
        return
    fi


    # get all topics if not specified
    if ! [ "$topics" ]; then

        if ! [ "$ACTIVE_REPO_DIR" ]; then
            error "Could not resolve active repo directory: $ACTIVE_REPO_DIR"
            msg "$( printf "Run %bdotsys install%b to configure a repo%s" $green $yellow "\n")"
            return 1
        fi
        local list="$(get_topic_list "$ACTIVE_REPO_DIR" "$force")"
        if ! [ "$list" ]; then
            if [ "$action" = "install" ]; then
                msg "$( printf "\nThere are no topics in %b$ACTIVE_REPO_DIR%b" $green $yellow)"
            else
                msg "$( printf "\nThere are no topics %binstalled by dotsys%b to $action" $green $yellow)"
            fi
        fi
        topics=("$list")
        debug "main -> topics list:\n\r$topics"
        debug "main -> end list"
    fi

    # We stub here rather then during symlink process
    # to get all user info up front for auto install
    if [ "$action" = "install" ] || [ "$action" = "upgrade" ] && in_limits "repo" "dotsys"; then
        manage_stubs $action "${topics[@]}"
    fi

    # Iterate topics

    debug "main -> TOPIC LOOP START"

    local topic

    for topic in ${topics[@]};do

        # ABORT: NON EXISTANT TOPICS
        if ! topic_exists "$topic"; then
            # error message supplied by topic_exits
            continue
        fi

        # LOAD TOPIC CONFIG (must be first and not in $(subshell) !)
        load_topic_config_vars "$topic"

        # ABORT: on platform exclude
        if platform_excluded "$topic"; then
            task "$(printf "Excluded %b${topic}%b on $PLATFORM" $green $blue)"
            continue
        fi

        # TOPIC MANGERS HAVE SPECIAL CONSIDERATIONS
        if is_manager "$topic"; then
            debug "main -> Handling manager: $topic"

            # All actions but uninstall
            if ! [ "$action" = "uninstall" ]; then
                debug "main -> ACTIVE_MANAGERS: ${ACTIVE_MANAGERS[@]}"
                # ABORT: Silently prevent managers from running more then once (even with --force)
                if [[ "${ACTIVE_MANAGERS[@]}" =~ "$topic" ]]; then
                    debug "main -> ABORT MANGER ACTION: Already ${action#e}ed $topic"
                    continue
                fi
                # create the state file
                touch "$(state_file "$topic")"
                # set active (prevents running manager tasks more then once)
                ACTIVE_MANAGERS+=("$topic")

            # uninstall is a bit different
            else

                # on uninstall we need to remove packages from package file first (or it will always be in use)
                if manager_in_use && in_limits "packages"; then
                    # TODO: URGENT all associated packages including topics are uninstalled
                    # the change get_package_list may not be wise, upgrade, freeze, run twice
                    # uninstall should be fine now since the topics are removed from state
                    # RETHINK package list results! probable stupid since manager_in_use already checks state
                    # no need for manage_packages to do it to, that will solve the problem!!!!!
                    # this may not be desirable, work though scenarios for best behavior
                    debug "main -> UNINSTALL MANAGER PACKAGES FIRST: $topic"
                    manage_packages "$action" "$topic" file "$force"
                fi

                # ABORT: uninstall if it's still in use (uninstalled at end as required).
                if manager_in_use "$topic"; then
                    warn "$(printf "Manager %b$topic%b is in use and can not be uninstalled yet." $green $rc)"
                    ACTIVE_MANAGERS+=("$topic")
                    debug "main -> ABORT MANGER IN USE: Active manager $topic can not be ${action%e}ed."
                    continue
                # now we can remove the sate file
                else
                    local sf="$(state_file "$topic")"
                    if [ -f "$sf" ]; then
                        debug "********* REMOVE STATE FILE $sf"
                        rm "$sf"
                    fi
                    # remove from active managers
                    ACTIVE_MANAGERS=( "${ACTIVE_MANAGERS[@]/$topic}" )
                fi
            fi

        # ABORT: Non manager topics when limited to managers
        else
            debug "main -> Handling topic: $topic"
            if in_limits "managers" -r; then
                debug "main -> ABORT: manager in limits and $topic is not a manger"
                continue
            fi
        fi


        # ABORT: on install if already installed (override --force)
        if [ "$action" = "install" ] && is_installed "dotsys" "$topic" && ! [ "$force" ]; then
           task "$(printf "Already ${action}ed %b$topic%b" $green $rc)"
           continue
        # ABORT: on uninstall if not installed (override --force)
        elif [ "$action" = "uninstall" ] && ! is_installed "dotsys" "$topic" && ! [ "$force" ]; then
           task "$(printf "Already ${action}ed %b$topic%b" $green $rc)"
           continue
        fi

        # CONFIRM TOPIC
        debug "main -> call confirm_task status: GC=$GLOBAL_CONFIRMED TC=$TOPIC_CONFIRMED"
        confirm_task "$action" "" "$topic" "${limits[@]}"
        if ! [ $? -eq 0 ]; then continue; fi
        debug "main -> post confirm_task status: GC=$GLOBAL_CONFIRMED TC=$TOPIC_CONFIRMED"


        # ALL CHECKS DONE START THE ACTION

        # 1) dependencies
        if [ "$action" = "install" ] && in_limits "scripts" "dotsys"; then
            install_dependencies "$topic"
        fi

        # 2) managed topics
        local topic_manager="$(get_topic_manager "$topic")"
        if [ "$topic_manager" ]; then

            # make sure the topic manager is installed on system
            if [ "$action" = "install" ] && ! is_installed "dotsys" "$topic_manager"; then
                info "$(printf "${action}ing manager %b$topic_manager%b for %b$topic%b" $green $rc $green $rc)"
                # install the manager
                dotsys "$action" "$topic_manager" ${limits[@]} --recursive
            fi

            # Always let manager manage topic
            debug "main -> END RECURSION calling run_manager_task: $topic_manager $action t:$topic $force"
            run_manager_task "$topic_manager" "$action" "$topic" "$force"
        fi

        # 3) symlinks
        if in_limits "links" "dotsys"; then
            debug "main -> call symlink_topic: $action $topic confirmed? gc:$GLOBAL_CONFIRMED tc:$TOPIC_CONFIRMED"
            symlink_topic "$action" "$topic"
        fi

        # 4) scripts
        if in_limits "scripts" "dotsys"; then
            debug "main -> call run_topic_script"
            run_topic_script "$action" "$topic"
        fi

        # 5) packages
        if [ "$action" != "uninstall" ] && is_manager && in_limits "packages"; then
            debug "main -> call manage_packages"
            manage_packages "$action" "$topic" file "$force"
        fi

        # track uninstalled topics
        if [ "$action" = "uninstall" ]; then
           UNINSTALLED_TOPICS+=(topic)
        fi
    done

    debug "main -> TOPIC LOOP END"

    # Finally check for repos and managers that still need to be uninstalled
    if [ "$action" = "uninstall" ]; then

        # Check for inactive managers to uninstall
        if in_limits "managers"; then
            debug "main -> clean inactive managers"
            local inactive_managers=()
            local m
            debug "main -> active_mangers: ${ACTIVE_MANAGERS[@]}"
            debug "main -> topics: ${topics[@]}"

            for m in ${ACTIVE_MANAGERS[@]}; do
                [[ "${topics[@]}" =~ "$m" ]]
                debug "main -> test for $m in topics = $?"
                if ! manager_in_use "$m" && [[ "${topics[@]}" =~ "$m" ]]; then
                    debug "main -> ADDING INACTIVE MANAGER $m"
                    inactive_managers+=("$m");
                fi
            done
            debug "main -> INACTIVE MANGERS: ${inactive_managers[@]}"
            if [ "${inactive_managers[@]}" ]; then
                debug "main -> uninstall inactive managers: $inactive_managers"
                dotsys uninstall ${inactive_managers[@]} ${limits[@]} --recursive
                return
            fi
        fi

        # Check if all repo topics are uninstalled & uninstall
        if in_limits "repo" && ! repo_in_use "$ACTIVE_REPO"; then
            debug "main -> REPO NO LONGER USED uninstalling"
            manage_repo "uninstall" "$ACTIVE_REPO" "$force"
        fi
    fi

    debug "main -> FINISHEÍD"
}


dotsys_installer () {

    local usage="dotsys_installer <action>"
    local usage_full="Installs and uninstalls dotsys.
    1) Put
    -i | install        install dotsys
    -x | uninstall      install dotsys
    "

    local action=
    case "$1" in
    -i | install )    action="$1" ;;
    -x | uninstall )  action="$1" ;;
    * )  error "Not a valid action: $1"
         show_usage ;;
    esac

    print_logo

    get_user_input "The installation of dotsys is designed to be minimal.
            $spacer However, we need to do a few things.  You can always
            $spacer run '.dotsys/installer.sh uninstall' to uninstall it."

    local current_shell="${SHELL##*/}"

    #TODO: need to make sure stubs are installed for current sheell and sourced.

    local dotfiles_dir="$(dotfiles_dir)"

    debug "$action dotsys DOTSYS_REPOSITORY: $DOTSYS_REPOSITORY"
    debug "$action dotsys user_dotfiles: $dotfiles_dir"

    # make sure PLATFORM_USER_BIN is on path
    if [ "${PATH#*$PLATFORM_USER_BIN}" == "$PATH" ]; then
        debug "adding /usr/local/bin to path"
        #TODO: .profile persists user bin on path, should we add to path file?
        export PATH=$PATH:/usr/local/bin
    fi

    #TODO: make sure all required dirs and files exist (ie state, user) then remove checks from funcs
    # create required directories
    if [ "$action" = "install" ]; then
        mkdir -p "$dotfiles_dir"
        mkdir -p "$DOTSYS_REPOSITORY/user/bin"
        mkdir -p "$DOTSYS_REPOSITORY/state"
        touch "$DOTSYS_REPOSITORY/state/dotsys.state"
        touch "$DOTSYS_REPOSITORY/state/user.state"
    fi

    # install/uninstall realpath
    run_script_func "realpath" "topic.sh"

    if cmd_exists realpath; then
        printf "$(realpath "$file")"
        return $?
    fi

    # symlink contents of .dotsys/bin
    symlink_topic "$action" dotsys

    # were going to have to do this
    #dotsys install shell bash zsh
}






