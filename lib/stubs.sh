#!/bin/sh


# Checks user's system for existing configs and move to repo
# Make sure this only happens for new user install process
# or those configs will not get loaded
add_existing_dotfiles () {
    local repo="${repo:-$ACTIVE_REPO}"
    local topic
    local topic_stubs

    confirm_task "add" "any existing original dotfiles from your system to" "dotsys" \
         "(we'll confirm each file before moving it)"
    if ! [ $? -eq 0 ]; then return;fi

    # iterate builtin topics
    for topic in $(get_dir_list "$(dotsys_dir)/builtins"); do

        # iterate topic sub files
        local topic_dir="$(repo_dir "$repo")/$topic"
        local stub_files="$(get_topic_stub_files "$topic")"
        local stub_dst
        local stub_target
        local stub_src
        debug "  add_existing_dotfiles topic = $topic"
        debug "  add_existing_dotfiles topic_dir = $topic_dir"
        debug "  add_existing_dotfiles stub_files = $stub_files"
        while IFS=$'\n' read -r stub_src; do
            debug "src = $stub_src"
            stub_dst="$(get_symlink_dst "$stub_src")"
            stub_target="$(get_topic_stub_target "$topic" "$stub_src")"
            #user_stub_file="$(dotsys_user_stub_file "$topic" "$stub_src")"

            # Check for existing original file only (symlinks will be taken care of during stub process)
            if ! [ -L "$stub_dst" ] && [ -f "$stub_dst" ]; then
                if [ -f "$stub_target" ]; then
                    get_user_input "$(printf "You have two versions of %b$(basename "$stub_dst")%b:
                            $spacer current version: %b$stub_dst%b
                            $spacer dotsys version: %b$stub_target%b
                            $spacer Which version would you like to use with dotsys
                            $spacer (Don't stress, we'll backup the other one)?" $thc $rc $thc $rc $thc $rc)" \
                            --true "current" --false "dotsys"

                    # keep system version: backup dotsys version before move
                    if [ $? -eq 0 ]; then
                        cp "$stub_target" "${stub_target}.dsbak"
                    # keep dotsys version: delete and backup system version
                    # symlink/stub process will take care of rest
                    else
                        mv "$stub_dst" "${stub_dst}.dsbak"
                        continue
                    fi

                else
                    confirm_task "move" "existing config file for" "$topic" \
                       "$(printf "%bfrom:%b $stub_dst" $thc $rc )" \
                       "$(printf "%bto:%b $stub_target" $thc $rc )"
                fi

                if ! [ $? -eq 0 ]; then continue;fi

                #create_user_stub "$topic" "$stub_src"

                # backup and move system version to dotsys
                cp "$stub_dst" "${stub_dst}.dsbak"
                mkdir -p "$(dirname "$stub_target")"
                mv "$stub_dst" "$stub_target"
                symlink "$stub_target" "$stub_dst"

            fi
        done <<< "$stub_files"
    done
}

# Collects all required user data at start of process
# Sources topic files
# Creates stub file in .dotsys/user/stub directory
# Stubs do not get symlinked untill topic is installed.
# However, since stubs are symlinked to user directory
# changes are instant and do not need to be relinked!
manage_stubs () {
    usage="manage_stubs [<option>]"
    usage_full="
        -f | --force        Force stub updates
        -d | --data         Collect user data
    "

    local action="$1"
    local topics=("$2")
    shift; shift

    #local builtins=$(get_dir_list "$(dotsys_dir)/builtins")
    local topic
    local force
    local mode

    while [[ $# > 0 ]]; do
        case "$1" in
        -f | --force )      force="$1" ;;
        -d | --data )       mode="$1" ;;
        *)  invalid_option ;;
        esac
        shift
    done

    if [ "$action" = "uninstall" ] || [ "$action" = "freeze" ]; then return;fi

    # check if user accepted subs and at least one topic
    if ! get_state_value "user" "use_stub_files" || ! [ "${topics[0]}" ]; then
        return
    fi

    debug "-- manage_stubs: $action ${topics[@]} $mode $force"

    if [ "$mode" = "--data" ]; then
        task "Collecting user data"
    else
        task "Sourcing topic files"
    fi

    for topic in ${topics[@]}; do
        # Abort core & shell till end
        #if [[ "${topics[*]}" =~ (core|shell) ]]; then continue; fi
        # Abort if not core or shell and no user topic
        if ! [[ "${topics[*]}" =~ (core|shell) ]] && ! [ -d "$(topic_dir "$topic" "user")" ]; then continue; fi
        manage_topic_stubs "$action" "$topic" "$mode" "$force"
    done

    if [ "$action" = "uninstall" ] && ! in_limits "dotsys" -r; then
        action="update"
    fi

#    # Core Always gets updated
#    manage_topic_stubs "$action" "core" "$mode"
#    # Shell always gets updated for sourcing topic .shell files
#    manage_topic_stubs "$action" "shell" "$mode"

}

# Create all stubs for a topic
manage_topic_stubs () {
    usage="manage_topic_stubs [<option>]"
    usage_full="
        -f | --force        Force stub updates
        -d | --data         Collect user data
    "
    local action="$1"
    local topic="$2"

    shift; shift

    local force
    local mode
    local stub_file
    local task

    while [[ $# > 0 ]]; do
        case "$1" in
        -f | --force )      force="$1" ;;
        -t | --task )       task="true" ;;
        -d | --data )       mode="data" ;;
        *)  invalid_option ;;
        esac
        shift
    done

    # Nothing to do on freeze or uninstall
    if [ "$action" = "freeze" ] || [ "$action" = "uninstall" ]; then
         return
    fi

    # Make sure user topic exits unless topic is core or shell
    if ! [[ "$topic" =~ (core|shell) ]] && ! [ -d "$(topic_dir "$topic" "user")" ]; then return; fi

    # Check for topic stub files
    local stub_files="$(get_topic_stub_files "$topic")"
    if ! [ "$stub_files" ]; then return; fi

    debug "-- manage_topic_stubs: $action $topic $mode $force"

    if [ "$task" ]; then
        task "Stubbing $topic $mode"
    fi

    while IFS=$'\n' read -r stub_file; do
        debug "   found stub file for $topic -> $stub_file"
        if [ "$mode" = "data" ]; then
            collect_user_data "$stub_file" "" "$force"
        else
            create_user_stub "$topic" "$stub_file" "$force"
        fi
    done <<< "$stub_files"
}


# create custom stub file in user/repo/topic
create_user_stub () {

    # stub file variables are defined as {TOPIC_VARIABLE_NAME}
    # ex: {GIT_USER_EMAIL} checks for git_user_email ins state defaults to global user_email
    # ex: {USER_EMAIL} uses global user_email (does not check for topic specif value)

    local topic="$1"
    local stub_src="$2"
    local mode="$3"
    local force="$4"

    local stub_name="$(basename "${stub_src%.*}")"
    local file_action="update"
    local has_source_files
    local variables
    local val

    # Convert stub_name to stub_src if required
    # This allows: create_user_stub "git" "gitconfig"
    if [ "$stub_src" = "$stub_name" ] ; then
        stub_src="$(builtin_topic_dir "$topic")/${stub_name}.stub"
    fi

    # abort if there is no stub for topic
    if ! [ -f "$stub_src" ]; then
        error "$topic does not have a stub file at:\n$stub_src"
        return
    fi

    local stub_tar="$(get_topic_stub_target "$topic" "$stub_src")"
    local stub_dst="$(dotsys_user_stub_file "$topic" "$stub_src")"
    local has_source_files="$(grep '{SOURCE_FILES}' "$stub_src")"

    # Create mode
    if ! [ -f "$stub_dst" ]; then
        file_action="create"

    # Update mode
    elif ! [ "$force" ] && ! [ "$has_source_files" ]; then
        # Abort if stub_dst is newer then source and correct target
        if [ "$stub_dst" -nt "$stub_src" ] && grep -q "$stub_tar" "$stub_dst" ; then
            debug "-- create_user_stub ABORTED (up to date): $stub_src"
            return
        fi
    fi

    debug "-- create_user_stub stub_src : $stub_src"
    debug "   create_user_stub stub_dst : $stub_dst"
    debug "   create_user_stub stub_tar : $stub_tar"

    # Create output file
    local stub_tmp="$(builtin_topic_dir "$topic")/${stub_name}.stub.tmp"
    local stub_out="$(builtin_topic_dir "$topic")/${stub_name}.stub.out"
    cp -f "$stub_src" "$stub_out"

    # update target
    debug "   create_user_stub update target"
    grep -q '{STUB_TARGET}' "$stub_out"
    if [ $? -eq 0 ]; then
        sed -e "s|{STUB_TARGET}|$stub_tar|g" "$stub_out" > "$stub_tmp"
        mv -f "$stub_tmp" "$stub_out"
        output="
        $spacer Stub Target : $stub_tar"
    fi

    # record sourced files
    if [ "$has_source_files" ]; then
        sed -e "s|{SOURCE_FILES}|${val}|g" "$stub_out" > "$stub_tmp"
        mv -f "$stub_tmp" "$stub_out"
        local sources="$(source_topic_files "$topic" "$stub_out" "true" | indent_lines --prefix "sourced : ")"
        if [ "$sources" ];then
            output="$output\n$sources"
        fi
    fi

    collect_user_data "$stub_out" "$stub_tmp"

    # move to .dotsys/user/stubs/stubname.topic.stub
    mv -f "$stub_out" "$stub_dst"
    local status=$?

    success_or_fail $status "$file_action" "stub file:" "$(printf "%b$topic $stub_name:" $thc )" "$output"
}

collect_user_data () {

    # TODO (IF NEEDED): IF more complex topic specific variables become necessary (like git) implement topic/*.stub.vars scripts to obtain values
    # get_custom_stub_vars $topic   # returns a list of "VARIABLE=value" pairs
    # variables+="$@"               # add "VARIABLE=value" pairs to variables

    debug "-- collect user data variables"
    local stub_out="$1"
    local stub_tmp="$2"
    local force="$3"
    local var
    local val
    local var_text
    local g_state_key
    local t_state_key
    local user_var
    local variables=($(sed -n 's|[^\$]*{\([A-Z_]*\)}.*|\1|gp' "$stub_out"))

    for var in ${variables[@]}; do
        # global key lower case and remove $topic_ or topic_
        g_state_key="$(echo "$var" | tr '[:upper:]' '[:lower:]')"
        g_state_key="${g_state_key#topic_}"
        g_state_key="${g_state_key#$topic_}"
        # topic key
        t_state_key="${topic}_${g_state_key}"
        # always use global key as text
        var_text="$(echo "$g_state_key" | tr '_' ' ')"

        case "$var" in
            SOURCE_FILES )              continue ;;
            STUB_TARGET )               continue;;
            DOTSYS_BIN )                val="$(dotsys_user_bin)";;
            USER_NAME )                 val="$USER_NAME";;
            CREDENTIAL_HELPER )         val="$(get_credential_helper)";;
            DOTFILES_DIR )              val="$(dotfiles_dir)" ;;
            DOTSYS_DIR )                val="$(dotsys_dir)" ;;
            DOTSYS_PLATFORM )           val="$(get_platform)" ;;
            DOTSYS_PLATFORM_SPE )       val="$(specific_platform "$(get_platform)")" ;;
            DOTSYS_PLATFORM_GEN )       val="$(generic_platform "$(get_platform)")" ;;
            *)                          val="$(get_state_value "user" "$t_state_key")"
                                        user_var="true" ;;
        esac

        # DO NOT REMOVE: If required for complex custom values
        # check for "VARIABLE=some value"
        # if ! [ "$val" ]; then
        #   val="${var%=}"                            # split value from "VARIABLE=value"
        #   var="${var#=}"                            # split variable from "VARIABLE=value"
        #   if [ "$var" = "$val"  ]; then val="";fi   # clear value if none provided
        # fi

        debug "   - create_user_stub pre-user input var($var) key($g_state_key) text($var_text) = $val"

        # Get user input if no val found
        if [[ ! "$val" && "$user_var" ]] || [ "$force" ]; then
            # use global_state_key value as default
            debug "   create_user_stub get default: $g_state_key"
            local def
            def="$(get_state_value "user" "${g_state_key}")"

            local user_input
            get_user_input "What is your $topic $var_text for $stub_name?" --options "omit" --default "${def:-none}" -r

            # abort stub process
            if ! [ $? -eq 0 ]; then return;fi

            # set user provided value
            val="${user_input:-$def}"

            # record user val to state
            set_state_value "user" "${topic}_state_key" "$val"

        elif ! [ "$stub_tmp" ];then
            success "$topic $var_text=$val"
        fi

        if [ "$stub_tmp" ]; then
            # modify the stub variable
            sed -e "s|{$var}|${val}|g" "$stub_out" > "$stub_tmp"
            mv -f "$stub_tmp" "$stub_out"
        fi

    done
}

get_topic_stub_files(){
    local topic="$1"
    local topic_dir="$(topic_dir "$topic" "active")"
    local builtin_dir="$(topic_dir "$topic" "builtin")"
    local dirs="$topic_dir $builtin_dir"
    local result="$(find $dirs -mindepth 1 -maxdepth 1 -type f -name '*.stub' -not -name '\.*' | sort -u)"
    echo "$result"
}

# returns the stub file symlink target
get_topic_stub_target(){
    local topic="$1"
    local stub_src="$2"
    local repo="$(get_active_repo)"

    # stub target should never be the builtin repo
    echo "$(topic_dir "$topic" "user")/$(basename "${stub_src%.stub}.symlink")"
}

remove_user_stub () {

    local topic="$1"
    local stub_src="$2"
    local force="$3"
    local stub_dst="$(dotsys_user_stub_file "$topic" "$stub_src")"
    rm "$stub_dst"
    success_or_fail $? "Remove" "sub file for" "$topic" ":\n$spacer ->$stub_dst"
}


# this is for git, may be useful else where..
get_credential_helper () {
    local helper='cache'
    if [[ "$PLATFORM" == *"mac" ]]; then
        helper='osxkeychain'
    fi
    echo "$helper"
}

# TODO: topic/stubfile.sh will likely be needed
# this works for shell script config files
# need solution for topics like vim with own lang
# use shell script to append source_topic_files to stub..
source_topic_files () {
    local topic="$1"
    local stub_file="$2"
    local return_files="$3"
    local installed_paths="$(get_installed_topic_paths)"
    local file
    local topic_dir
    local OWD="$PWD"

    local order="path functions aliases"

    local files

    debug "   source_topic_files for stub file: $stub_file"

    for topic_dir in $installed_paths; do
        local sourced=()
        local o

        # source ordered files
        for o in $order; do
            file="$(find "$topic_dir" -mindepth 1 -maxdepth 1 -type f -name "$o.$topic" -not -name '\.*' )"
            if ! [ "$file" ]; then continue; fi
            echo source "$file" >> $stub_file
            if [ "$return_files" ]; then
                echo "$file"
            fi
            sourced+=("$file")
        done

        # source topic files of any name
        local topic_files="$(find "$topic_dir" -mindepth 1 -maxdepth 1 -type f -name "*.$topic" -not -name '\.*' )"
        while IFS=$'\n' read -r file; do
            if ! [ "$file" ] || [[ ${sourced[@]} =~ $file ]]; then continue;fi
            echo source "$file" >> $stub_file
            if [ "$return_files" ]; then
                echo "$file"
            fi


        done <<< "$topic_files"
    done

}

SYSTEM_SH_FILES="manager.sh topic.sh install.sh update.sh upgrade.sh freeze.sh uninstall.sh"