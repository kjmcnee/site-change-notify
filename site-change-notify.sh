#!/bin/bash
# site-change-notify.sh
# Notifies user if any tracked sites have changed

usage(){
    echo "Usage: ${0} [options...]" >&2
    echo "Options:" >&2
    echo -e "\t-h,--help\n\t\tdisplay this help and exit" >&2
    echo -e "\t-a,--add SITE\n\t\ttrack changes to SITE" >&2
    echo -e "\t-r,--remove SITE\n\t\tno longer track SITE" >&2
    echo -e "\t-n,--just-notify\n\t\tif a site has changed, future executions of this script will still ckeck against the older version of the site instead of the current one" >&2
    echo -e "\t-f,--fatal\n\t\tif a request to a site fails, exit imediately (do not make requests for other sites)" >&2
    exit 1
}

# defaults (0 is true, 1 is false)
just_notify=1
fatal=1

# this file stores the url of each site along with a hash of the contents for use in comparisons
site_hash_file="${HOME}/.site-change-notify-hashes"
# if it doesn't exist, create it
[ -f "${site_hash_file}" ] || > "${site_hash_file}"

# select the command for the hash (Mac uses md5; Linux uses md5sum)
if type md5 &> /dev/null ; then
    hash_cmd='md5'
elif type md5sum &> /dev/null ; then
    hash_cmd='md5sum'
else
    echo "Error: Unable to find a command which creates md5 hashes." >&2
    exit 1
fi


# hashes the site's contents and stores result in variable ${hash}
# $1 is the site
# returns 0 if request was successful, 1 otherwise
site_hash(){
    content=$(curl --silent ${1})
    if [ $? -ne 0 ]; then
        hash=""
        echo "Query failed for site ${1}" >&2
        return 1
    else
        hash=$(echo ${content} | ${hash_cmd} | cut -d" " -f1)
        return 0
    fi
}

# add site to file of sites to be tracked
# $1 is the site
add_site(){
    # check if site is already tracked
    while read line; do
        if [ "$(echo ${line} | cut -d"|" -f1)" = "${1}" ]; then
            echo "${1} is already being tracked." >&2
            return
        fi
    done < "${site_hash_file}"
    
    # if the site is not already tracked, attempt to get a hash of its content
    site_hash "${1}"

    # if query is successful
    if [ $? -eq 0 ]; then
        echo -e "${1}|${hash}" >> "${site_hash_file}"
        echo Tracking site: ${1}
    else
        echo "Site not added" >&2
        if [ ${fatal} -eq 0 ]; then
            echo "Aborting" >&2
            exit 1
        fi
    fi
}

# remove site from file of sites to be tracked
# $1 is the site
remove_site(){
    cp "${site_hash_file}"{,.bak}
    grep -v "${1}" "${site_hash_file}.bak" > "${site_hash_file}"
    rm "${site_hash_file}.bak"
}

# parse command line options
while [ $# -gt 0 ] ; do
    case "${1}" in
        -a | --add)
            [ $# -lt 2 ] && usage
            add_site "${2}"
            shift 2
            ;;
        -r | --remove)
            [ $# -lt 2 ] && usage
            remove_site "${2}"
            shift 2
            ;;
        -n | --just-notify)
            just_notify=0
            shift
            ;;
        -f | --fatal)
            fatal=0
            shift
            ;;
        -h | --help)
            usage
            ;;
        *)
            echo "Unknown option: ${1}" >&2
            usage
            ;;
    esac
done

# check for changes
while read line; do
    site="$(echo ${line} | cut -d"|" -f1)"
    prev_hash="$(echo ${line} | cut -d"|" -f2)"
    
    site_hash "${site}"

    # if query is successful
    if [ $? -eq 0 ]; then
        # if the site has been changed
        if [ "${hash}" != "${prev_hash}" ]; then
            
            echo Site changed: ${site}

            # update hash in file
            if [ ${just_notify} -eq 1 ] ; then
                cp "${site_hash_file}"{,.bak}
                sed "s/${prev_hash}/${hash}/g" "${site_hash_file}.bak" > "${site_hash_file}"
                rm "${site_hash_file}.bak"
            fi
        fi
    elif [ ${fatal} -eq 0 ]; then
        echo "Aborting" >&2
        exit 1
    fi

done < "${site_hash_file}"
