#!/bin/sh

### SOURCE ###
# https://gitlab.com/skywiz-io/terraformig

### LICENSE ###
# MIT License

# Copyright (c) 2020 TeraSky and Yeshayahu Wasserman

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

### CONFIGURATION ###
set -e # Exit when any command fails

### GLOBAL VARIABLES ###
TERRAFORMIG_VERSION="0.1.0"

### FUNCTIONS ###
print_readme(){
cat << EOF

This script provides a migration tool to move any number of resources from one statefile to another (including remote backends).

Prerequisites:
  * Terraform version 12.13+ (Untested on earlier versions, but may work).
  * jq version >= jq-1.5-1-a5b5cbe (Untested on earlier versions, but may work).
  * Script MUST be run from Source Terraform directory; from which you wish to extract resources.

Directions:
  * Move the Terraform code (that defines the resources you wish to move) to the Target directory.
    > Option 1: Separate the terraform resources to a separate .tf file and then move the whole file to the Target directory.
    > Option 2: Cut and paste each resource/module block from the current (Source) directory and paste in a .tf (usually main.tf) file at the Target directory.

Usage: terraformig [-options] <command> [src path] [dest path]
  * src path          Path to source terraform directory 
                        Defaults to current working directory
  * dest path         Path to destination terraform directory
 
Commands:
    apply             Moves resouces/modules between states
    plan              Runs migration tool in DRY_RUN mode without modifying states
    purge             Deletes backup files created by this tool in both SRC and DEST Terraform directories
    rollback          Recovers previous states in both SRC and DEST Terraform directories

Options:
    -cleanup          CAUTION: Only use if you know what you're doing!
                        Cleans up any backup files at the successful conclusion of this script
    -debug            Enabled DEBUG mode and prints otherwise hidden output
    -help             Prints this script's README
    -version          Prints this tool's version

EOF
}

info_print(){
  printf "\n[INFO] - %s\n" "$*"
  sleep 2
}

debug_print(){
  printf "\n[DEBUG] - %s\n" "$*"
  sleep 1
}

error_print(){
  printf "\n[ERROR] - %s. \
  \n          Exiting...\n\n" \
  "$*"
  exit 1
}

backup_warning(){
  printf "\n[WARN] - There already exists a backup made by this script. \
  \n         Please remove or rename it and then try again. \
  \n         You may wish to run the \"purge\" command. \
  \n         Exiting...\n\n"
  exit 1
}

cleanup_backups(){
  info_print "Cleaning up all backup files."
  cd ${START_DIR}
  cd $TF_SRC_DIR
  rm -rf terraformig.tfstate*
  cd ${START_DIR}
  cd $TF_DEST_DIR
  rm -rf terraformig.tfstate*
}

error_handler(){
  printf "\n[ERROR] - Something went wrong. \
  \n          You may wish to add the \"-debug\" flag to your command. \
  \n          Exiting...\n\n"
}

### DEFAULT VARIABLES ###
CLEANUP_BACKUPS=0
DEBUG=0
PURGE=0
OTHER_ARGUMENTS=()
TF_SRC_DIR=$(pwd)
NUM_OF_ARGS=$#
HELP=0
DRY_RUN=0
APPLY=0
VERSION=0
START_DIR=$(pwd)

### MAIN ###
trap "error_handler" ERR

# Loop through arguments and process them
for arg in "$@"
do
    case $arg in
        -cleanup)
        CLEANUP_BACKUPS=1
        shift
        ;;
        -version)
        VERSION=1
        shift
        ;;
        -debug)
        DEBUG=1
        shift
        ;;
        purge)
        PURGE=1
        shift
        ;;
        -help)
        HELP=1
        shift
        ;;
        plan)
        DRY_RUN=1
        CLEANUP_BACKUPS=1
        shift
        ;;
        apply)
        APPLY=1
        shift
        ;;
        *)
        OTHER_ARGUMENTS+=("$1")
        shift
        ;;
    esac
done

TF_DEST_DIR=${OTHER_ARGUMENTS[0]}
if [[ ${#OTHER_ARGUMENTS[@]} -gt 1 ]]; then
  TF_SRC_DIR="${OTHER_ARGUMENTS[0]}"
  TF_DEST_DIR="${OTHER_ARGUMENTS[1]}"
fi

if [[ $NUM_OF_ARGS -eq 0 || $HELP -eq 1 ]] || [[ $APPLY -eq 0 && $DRY_RUN -eq 0 && $PURGE -eq 0 ]]; then
  print_readme
  exit 0
fi

if [[ $VERSION -eq 1 ]]; then
  info_print "TerraforMig v$TERRAFORMIG_VERSION"
  exit 0
fi

if [[ -z "$TF_DEST_DIR" ]]; then
  if [[ ${BASH_VERSINFO[0]} < 4 ]]; then
    read -e -p "Are you ready to continue? [y/N] " answer
  else
    read -e -p "Are you ready to continue? " -i "yes" answer
  fi
  if [[ $answer != "yes" && $answer != "y" ]]; then
    printf "Canceled\n"
    exit 0
  fi
fi

if [[ $DRY_RUN -eq 1 ]]; then
  info_print "DRY_RUN mode enabled. Nothing will be moved. Only temporary backups and plans will be created."
fi

# Check if string is empty using -z
while [[ -z "$TF_DEST_DIR" ]]; do
  info_print "Current directory (\$pwd): $(pwd)
  "
  read -p "Please enter the destination terraform directory (include path): " TF_DEST_DIR
done
if [[ ! -d $TF_DEST_DIR ]]; then
  error_print "Could not locate destination terraform directory at: \"$TF_DEST_DIR\""
fi

if [[ $PURGE -eq 1 ]]; then
  info_print "Purging previous backups performed by this tool..."
  cleanup_backups
  info_print "Purge complete. Exiting..."
  exit 0
fi

cd ${START_DIR}
cd ${TF_SRC_DIR}
info_print "Ensuring source terraform directory is initialized."
TF_SRC_INIT=$(terraform init -input=false)
if [[ $DEBUG -eq 1 ]]; then
  debug_print "$TF_SRC_INIT"
fi

info_print "Creating source statefile backup titled \"terraformig.tfstate.backup\" before modifying."
if [[ -f terraformig.tfstate.backup ]]; then
  backup_warning
fi
terraform state pull > terraformig.tfstate.backup

cd ${START_DIR}
cd ${TF_DEST_DIR}
info_print "Ensuring destination terraform is initialized."
TF_DEST_INIT=$(terraform init -reconfigure -input=false)
if [[ $DEBUG -eq 1 ]]; then
  debug_print "$TF_DEST_INIT"
fi
TF_BACKEND_EXIST=0
TF_BACKEND_STR="Successfully configured the backend"
if [[ "$TF_BACKEND_STR" == *"$TF_DEST_INIT"* ]]; then
  debug_print "It's there!"
  TF_BACKEND_EXIST=1
fi
info_print "Creating destination statefile backup titled \"terraformig.tfstate.backup\" before modifying."
if [[ -f terraformig.tfstate.backup ]]; then
  backup_warning
fi
terraform state pull > terraform.tfstate
cp terraform.tfstate terraformig.tfstate.backup

cd ${START_DIR}
cd $TF_SRC_DIR
info_print "Creating temporary terraform plan file."
terraform plan -out=terraformig.tfplan > /dev/null

CMD() {
  terraform show -json terraformig.tfplan | jq -r '.resource_changes[] | select(.change.actions[] | contains ("delete")) | .address'
}
count=0
previous=
current=
for n in $(CMD)
do
  current=$n
  if [[ $current == "module."* ]]; then
    current=$(echo $current | cut -d'.' -f1,2)
    if [[ $current == $previous ]]; then
      continue
    fi
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    info_print "DRY_RUN mode enabled. Would move $current resource/module."
  else
    info_print "Moving $current resource/module..."
    terraform state mv -state-out=${TF_DEST_DIR}/terraform.tfstate $current $current
  fi
  previous=$current
  count=$((count + 1))
done
rm -f terraformig.tfplan

if [[ $count -eq 0 ]]; then
  info_print "0 resources to move."
  info_print "Did you remove the resource definitions from the source config files?"
else
  cd ${START_DIR}
  cd ${TF_DEST_DIR}
  rm -f ./.terraform/terraform.tfstate
  info_print "Initializing destination terraform with updated statefile."
  TF_DEST_UPDATE_INIT=$(terraform init -force-copy -input=false)
  if [[ $DEBUG -eq 1 ]]; then
    debug_print "$TF_DEST_UPDATE_INIT"
  fi
fi

if [[ $TF_BACKEND_EXIST -eq 1 ]]; then
  rm -f terraform.tfstate
fi

if [[ $CLEANUP_BACKUPS -eq 1 ]]; then
  cleanup_backups
fi

info_print "Finished!"
