#!/bin/bash
SHELL=/bin/bash

# Get the current working directory
workdir=$(pwd)
file_config="autoupdate.config"

# Print the current working directory
echo $workdir

# Function for printing debug messages with timestamps
debug_print(){
    local datetime=$(date +"%Y/%m/%d %H:%M:%S")
    echo "[${datetime}] ${1}: ${2}" 
    #echo "[${datetime}] ${1}: ${2}" >> autoupdate.log
} 

# Terminate the program with an informative message
quit(){
    debug_print "Info" "Program is terminated. (3 second)"
    sleep 3
    echo "Good bye..."
    exit
}

# Check if the config file exists, if not, exit
if [ ! -f  "${workdir}/${file_config}" ]; then
    debug_print "Info" "Config file not found !"
    quit
fi

# Read the config file and set variables accordingly
while read preset; do
    if [ ! ${preset:0:1} == "#" ]; then
        declare "$preset";
    fi
done < "${workdir}/${file_config}"

# Construct paths and filenames
build_path="${workdir}/${build_path}"
backup_path="${workdir}/${backup_path}"

build_file=$file_name.$extension_type
build_file_path="${build_path}/${build_file}"

# Function to check if a package is installed, install if not
check_package(){
    PKG_OK=$(dpkg-query -W --showformat='${Status}\n' ${1}|grep "install ok installed")

    if [ "" == "$PKG_OK" ]; then
        debug_print "Warning" "Not installed package (${1})"
        sudo apt-get --yes install ${1}
    else
        debug_print "Info" "Installed package (${1})"
    fi
}

# Check all required packages from a file
check_all_package(){
    # Read requirements file
    debug_print "Info" "Check all package."
    while read package; do
        check_package "$package";
    done < requirements.txt
}

# Function to check directory permissions
check_dir_perm(){
    if [ -e "${1}" ]; then
        if [ -d "${1}" ] && [ -w "${1}" ] && [ -x "${1}" ]; then
            return 0
        else
            return 1
        fi
    else
        check_dir_perm "$(dirname "${1}")"
        return $?
    fi
}

# Check a directory, create if necessary
check_dir(){
    check_dir_perm "${1}"
    local result_perm=$?

    if [ $result_perm == 1 ]; then
        debug_print "Warning" "Directory Permission denied ! (${1})"
        return 1
    fi 

    if [ ! -d "${1}" ]; then
        debug_print "Info" "Directory not found ! (${1})"
        mkdir "${1}"
        debug_print "Info" "Created directory (${1})"
        return 0
    else
        debug_print "Info" "Directory was found (${1})"
        return 0
    fi
}

# Check all required directories
check_all_dir(){
    debug_print "Info" "Check all directory."
    all_dir=($build_path $backup_path $extract_path)

    for dir in ${all_dir[@]}; do
        check_dir $dir
        local result=$?

        if [ $result == 1 ]; then
            debug_print "Warning" "Directory access not found ! (${dir})"
            return 1
        fi
    done
    return 0
}

# Check if a file exists
check_file(){
    if [ ! -f  "${1}" ]; then
        debug_print "Info" "File not found ! (${1})"
        return 1
    else
        debug_print "Info" "File found. (${1})"
        return 0
    fi
}

# Delete a file if it exists
delete_file(){
    debug_print "Info" "Deleting file..."
    check_file "${1}"
    if [ $? == 1 ]; then
        debug_print "Warning" "Cannot continue because file does not exist. (${1})"
        return 1
    else
        rm "${1}"
        check_file "${1}"
        if [ $? == 1 ]; then
            debug_print "Info" "File successfully deleted. (${1})"
            return 0
        else
            debug_print "Warning" "File could not be deleted. (${1})"
            return 1
        fi
    fi
}

# Check if a directory is empty
dir_is_empty(){
    if [ "$(ls -A ${1})" ]; then
        debug_print "Warning" "Directory is not empty ! (${1})"
        return 1
    fi
    debug_print "Info" "Directory is empty. (${1})"
    return 0
}

# Clean a directory by deleting its contents
clean_dir(){
    debug_print "Info" "Cleaning up the directory..."
    if [ "${1}" == "/" ]; then
        debug_print "Warning" "Wrong directory path ! (${1})"
        return 1
    fi
    check_dir "${1}"
    local result_check_dir=$?
    if [ $result_check_dir == 1 ]; then
        debug_print "Warning" "Directory access not found ! (${1})"
        return 1
    elif [ $result_check_dir == 0 ]; then
        debug_print "Info"

 "Deleting directory all contents..."
        rm -rf ${1}/*
        dir_is_empty "${1}"
        if [ $? == 1 ]; then
            debug_print "Warning" "Could not clean directory ! (${1})"
            return 1
        else
            debug_print "Info" "Directory successfully cleared. (${1})"
            return 0
        fi
    fi
}

# Check if an archive is valid
check_archive(){
    debug_print "Info" "Checking up archive... (${1})"
    local result=$(zip -T "${1}")
    if grep -q "OK" <<< "${result}" ; then
        debug_print "Info" "Archive is good. (${1})"
        return 0
    else
        debug_print "Error" "Archive is corrupt ! (${1})"
        return 1
    fi
}

# Extract an archive to a specific directory
extract_archive(){
    debug_print "Info" "Extracting archive... (${1})"
    clean_dir "${2}"
    local result_clean_dir=$?
    if [ $result_clean_dir == 1 ]; then
        return 1
    fi
    local result_extract=$(unzip -o ${1} -d ${2})
    debug_print "Info" "Archive successfully extracted. (${1})"
    return 0
}

# Create a backup of a file
take_backup(){
    local datetime=$(date +"%Y-%m-%dT%H-%M-%S")
    local backup_file="backup_${datetime}.${extension_type}"
    local backup_location="${backup_path}/${datetime}.${extension_type}"

    if [ "${backup}" == "yes" ]; then
        check_dir ${backup_path}
        local result_check_dir=$?

        if [ $result_check_dir == 1 ]; then
            debug_print "Warning" "Backup permission failed ! (${backup_file})"
            return 1
        fi

        cp "${1}" "$backup_location"

        if [ -f "${backup_location}" ]; then
            debug_print "Info" "Backup taken successfully (${backup_file})"
            return 0
        else
            debug_print "Warning" "Backup taken failed (${backup_file})"
            return 1
        fi   
    fi
}

# Update process
update(){
    # Check if the build file exists
    check_file "${build_file_path}"
    if [ $? == 1 ]; then
        debug_print "Info" "Cannot continue because file does not exist."
        return 2
    fi

    # Check the validity of the build file archive
    check_archive "${build_file_path}"
    if [ $? == 1 ]; then
        debug_print "Warning" "Cannot continue because corrupt archive."
        return 1
    fi

    # Extract the build file archive to the extract path
    extract_archive "${build_file_path}" "${extract_path}"
    if [ $? == 1 ]; then
        debug_print "Warning" "Cannot continue because could not extract archive."
        return 1
    fi

    # Create a backup of the build file and delete it
    take_backup "${build_file_path}"
    local result_take_backup=$?
    delete_file "${build_file_path}"
    local result_delete_file=$?
    if [ $result_take_backup == 1 ]; then
        debug_print "Warning" "Backup skipped."
    fi

    if [ $result_delete_file == 1 ]; then
        debug_print "Warning" "Deleting skipped."
    fi

    if [ $result_take_backup == 1 ] || [ $result_delete_file == 1 ]; then
        return 3
    fi
    return 0
}

# Trigger an API
api_trigger(){
    debug_print "Info" "API is triggering..."
    local api_result_code=$(curl -sb -H "Accept: application/json" "${1}" | jq -r '.statusCode')
    debug_print "Info" "API Result Code (${api_result_code})"
    if [ $api_result_code == 200 ]; then
        debug_print "Info" "API result message OK."
        return 0
    fi
    return 1
}

# Create a new image using an API
create_image(){
    debug_print "Info" "Creating new Image..."
    api_trigger "${api_url}"
    local result_api=$?
    if [ $result_api == 0 ]; then
        debug_print "Info" "New Image successfully created."
        return 0
    elif [ $result_api == 1 ]; then
        debug_print "Warning" "Could not create new image !"
        return 1
    fi
}

# Repeatedly perform update and image creation
repeat(){
    update
    local result_update=$?
    if [ $result_update == 0 ]; then
        debug_print "Info" "Update successfully."
        create_image
    elif [ $result_update == 1 ]; then
        debug_print "Error" "Update failed."
    elif [ $result_update == 2 ]; then
        debug_print "Info" "Update skipped."
    elif [ $result_update == 3 ]; then
        debug_print "Warning" "Update but some steps were skipped."
    fi
    debug_print "Info" "Waiting for new update... (${repeat_time} second)"
    sleep $repeat_time
    debug_print "Info" "Checking for re-update..."
    repeat
}

# Check everything before starting the process
check_all(){
    debug_print "Info" "Check all."
    check_all_package
    check_all_dir
    if [ $? == 1 ]; then
        debug_print "Warning" "Directories check failed."
        return 1
    fi
    return 0
}

# Initialize the auto-update process
initialize(){
    debug_print "Info" "Initialize."
    check_all
    if [ $? == 1 ]; then
        debug_print "Warning" "Checking failed."
        quit
    else
        debug_print "Info" "All checks are successful."
    fi
    debug_print "Info" "Checking for update..."
    repeat
}

# Print ASCII art and start the process
print_ascii_art(){
    ascii_art=$'
    ⣿⣿⡆⠀⠀⢸⣷⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⡇⠀⠀⣾⣿⡆
    ⣿⣿⡇⠀⠀⢸⣿⢰⣿⡆⠀⣾⣿⡆⠀⣾⣷ ⣿⣿⡇⠀⠀⣿⣿⡇
    ⣿⣿⡇⠀⠀⢸⣿⠘⣿⣿⣤⣿⣿⣿⣤⣿⡇⢻⣿⡇⠀⠀⣿⣿⡇
    ⣿⣿⡇⠀⠀⢸⡿⠀⢹⣿⣿⣿⣿⣿⣿⣿⠁⢸⣿⣇⠀⢀⣿⣿⠇
    ⠙⢿⣷⣶⣶⡿⠁⠀⠈⣿⣿⠟⠀⣿⣿⠇⠀⠈⠻⣿⣶⣾⡿⠋'


    while IFS= read -r line; do
        echo "$line"
    done <<< "$ascii_art"
    echo ""
}


# Print ASCII art and initialize the process
print_ascii_art
initialize
